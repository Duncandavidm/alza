import SwiftUI

/// Pantalla de confirmacion despues de un escaneo valido: el usuario
/// escribe el monto (la DGI no lo manda en el QR), confirma o cambia la
/// categoria, y si hay un gasto parecido ese mismo dia, decide si
/// fusionar en vez de duplicar.
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

    private var amount: Decimal {
        Decimal(string: draft.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Factura") {
                    LabeledContent("Comercio", value: draft.merchant?.name ?? "Sin identificar (RUC \(draft.parsed.fields.ruc))")
                    LabeledContent("Fecha", value: draft.parsed.fields.fechaISO)
                    LabeledContent("Sucursal", value: draft.parsed.fields.sucursal)
                }

                Section {
                    AmountField(placeholder: "Monto de la factura", text: $draft.amountText)
                        .onChange(of: draft.amountText) { _, _ in
                            Task { await checkMerge() }
                        }

                    Picker("Categoría", selection: $draft.category) {
                        Text("Sin categoría").tag(TransactionCategory?.none)
                        ForEach(TransactionCategory.allCases) { category in
                            Text("\(category.emoji) \(category.rawValue)").tag(Optional(category))
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
                    Text("El monto se registra de una vez; los puntos se acreditan cuando la DGI confirme la factura (24-72 h).")
                }

                if let candidate = draft.mergeCandidate {
                    Section {
                        Toggle(isOn: $draft.mergeWithCandidate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unir con un gasto que ya tienes")
                                Text("\(candidate.description ?? candidate.movementType.displayName) — \(candidate.amount, format: .currency(code: "USD")), mismo día")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text(draft.mergeWithCandidate
                             ? "Vamos a vincular la factura a ese movimiento, sin crear uno nuevo."
                             : "Se va a crear un movimiento nuevo aparte.")
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
                    Button("Guardar") { Task { await save() } }
                        .disabled(amount <= 0 || selectedAccountId == nil || isSaving)
                }
            }
            .onAppear {
                selectedAccountId = selectedAccountId ?? accounts.first?.id
            }
        }
    }

    private func checkMerge() async {
        guard let userId = appState.currentUserId, amount > 0, checkedMergeForAmount != amount else { return }
        checkedMergeForAmount = amount
        draft.mergeCandidate = await viewModel.mergeCandidate(for: draft, userId: userId, amount: amount)
    }

    private func save() async {
        guard let userId = appState.currentUserId, let accountId = selectedAccountId else { return }
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
