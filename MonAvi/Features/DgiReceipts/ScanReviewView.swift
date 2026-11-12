import SwiftUI

/// Pantalla de confirmacion despues de un escaneo valido. Si pudimos leer
/// la factura, el monto, el comercio, la fecha y la categoria ya vienen
/// llenos (el monto bloqueado, con opcion de "Editar"); si no, el usuario
/// escribe el monto como siempre. Si hay un gasto parecido ese mismo dia,
/// decide si fusionar en vez de duplicar.
struct ScanReviewView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DgiReceiptsViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void

    @State var draft: ScanDraft
    @State private var selectedAccountId: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var checkedMergeForAmount: Decimal?
    @State private var isShowingIncomeForm = false
    @StateObject private var incomeViewModel = DashboardViewModel()

    private var amount: Decimal {
        Decimal(string: draft.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Solo se puede unir con un gasto existente cuando NO se separa por
    /// categoria.
    private var isSplitting: Bool {
        draft.splitByCategory && draft.canSplitByCategory
    }

    private var splitPreview: [DgiCategorySplitLine] {
        DgiInvoiceLookupLogic.splitLines(breakdown: draft.invoiceDetails?.breakdown ?? [], total: amount)
    }

    private var dateText: String {
        if let authorizedAt = draft.authorizedAt {
            return authorizedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: .monavi))
        }
        return DgiReceiptDateFormat.date(from: draft.parsed.fields.fechaISO)
            .formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Factura") {
                    LabeledContent("Comercio", value: draft.merchantDisplayName ?? "Sin identificar (RUC \(draft.parsed.fields.ruc))")
                    LabeledContent("Fecha", value: dateText)
                    LabeledContent("Sucursal", value: draft.parsed.fields.sucursal)
                    if let details = draft.invoiceDetails, !details.paymentMethods.isEmpty {
                        LabeledContent(
                            details.paymentMethods.count > 1 ? "Formas de pago" : "Forma de pago",
                            value: details.paymentMethods.joined(separator: ", ")
                        )
                    }
                }

                if let details = draft.invoiceDetails, !details.items.isEmpty {
                    Section {
                        DisclosureGroup("Productos (\(details.items.count))") {
                            ForEach(details.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                }

                lookupNoticeSection

                Section {
                    amountRow

                    if !isSplitting {
                        Picker("Categoría", selection: $draft.category) {
                            Text("Sin categoría").tag(TransactionCategory?.none)
                            ForEach(TransactionCategory.allCases) { category in
                                Text("\(category.emoji) \(category.rawValue)").tag(Optional(category))
                            }
                        }
                    }

                    Picker("Cuenta", selection: $selectedAccountId) {
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } header: {
                    Text("Monto y categoría")
                } footer: {
                    Text("El gasto se registra de una vez. Verificamos tu factura al guardarla: si ya está publicada, tu cashback (1%) se suma enseguida; si no, la volvemos a revisar en 24 horas y queda pendiente hasta confirmarla.")
                }

                if draft.canSplitByCategory {
                    Section {
                        ForEach(splitPreview) { line in
                            LabeledContent {
                                Text(line.amount, format: .currency(code: "USD"))
                            } label: {
                                Text("\(line.category?.emoji ?? "🏷️") \(line.categoryName)")
                            }
                        }
                    } header: {
                        Text("Gastos que se registran")
                    } footer: {
                        Text("Se registra un gasto por cada categoría, con la misma cuenta y fecha.")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Confirmar factura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aceptar") { Task { await save() } }
                        .disabled(amount <= 0 || selectedAccountId == nil || isSaving || draft.isDuplicate)
                }
            }
            .onAppear {
                selectedAccountId = selectedAccountId ?? accounts.first?.id
            }
            .task {
                // Con el monto ya leido de la factura, ofrecer de una vez
                // la fusion con un gasto parecido del mismo dia.
                await checkMerge()
            }
            .sheet(isPresented: $isShowingIncomeForm) {
                AddTransactionView(
                    viewModel: incomeViewModel,
                    accounts: accounts,
                    initialMovementType: .ingreso
                )
            }
        }
    }

    @ViewBuilder
    private var amountRow: some View {
        if draft.isAmountEditable {
            AmountField(placeholder: "Monto de la factura", text: $draft.amountText)
                .onChange(of: draft.amountText) { _, _ in
                    Task { await checkMerge() }
                }
        } else {
            HStack {
                Text("Monto")
                Spacer()
                Text(amount, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
                Button("Editar") {
                    draft.isAmountEditable = true
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var lookupNoticeSection: some View {
        switch draft.lookup {
        case .duplicate(let message, _):
            Section {
                Text(message)
                    .foregroundStyle(.red)
            }
        case .rateLimited:
            Section {
                Text("No pudimos leer tu factura ahorita. Escribe el monto y la verificamos después.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .manual:
            Section {
                Label {
                    Text("Tu factura aún no aparece publicada. Escribe el monto: la guardamos, la volvemos a revisar en 24 horas y tu cashback queda pendiente hasta confirmarla.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                }
            }
        case .confirmed, .failed:
            EmptyView()
        }

        if draft.lookup.showsIncomeNotice {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Tu gasto se registra igual. Para recibir el cashback de esta factura, registra tus ingresos del mes: el cashback se respalda con lo que ganas.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    Button("Registrar ingreso") {
                        isShowingIncomeForm = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(accounts.isEmpty)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func itemRow(_ item: DgiInvoiceItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .font(.subheadline)
                if let quantity = item.quantity {
                    Text("Cant. \(quantity.formatted(.number.precision(.fractionLength(0...3)).locale(.monavi)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let total = item.total {
                Text(total, format: .currency(code: "USD"))
                    .font(.subheadline)
            }
        }
    }

    private func checkMerge() async {
        guard let userId = appState.currentUserId, amount > 0, checkedMergeForAmount != amount else { return }
        checkedMergeForAmount = amount
        draft.mergeCandidate = await viewModel.mergeCandidate(for: draft, userId: userId, amount: amount)
    }

    private func save() async {
        guard let userId = appState.currentUserId, let accountId = selectedAccountId, !draft.isDuplicate else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.confirmScan(draft: draft, userId: userId, accountId: accountId, amount: amount)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
