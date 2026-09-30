import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DashboardViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false

    @State private var selectedAccountId: UUID?
    @State private var amountText = ""
    @State private var movementType: MovementType = .gasto
    @State private var category: TransactionCategory = .other
    @State private var description = ""
    @State private var tagsText = ""
    @State private var selectedCurrency = "USD"
    @State private var isConverting = false
    @State private var isSaving = false
    @State private var showingSavingAnimation = false
    @State private var errorMessage: String?

    /// "#cine #viaje" -> ["cine", "viaje"] (inspirado en "Buscar con Etiquetas").
    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : String($0) }
            .filter { !$0.isEmpty }
    }

    private var enteredMagnitude: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId }
    }

    private var isForeignCurrency: Bool {
        guard let accountCurrency = selectedAccount?.currency else { return false }
        return selectedCurrency != accountCurrency
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MovementTypePicker(selection: $movementType)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                }

                Picker("Cuenta", selection: $selectedAccountId) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                TextField("Monto", text: $amountText)
                    .keyboardType(.decimalPad)

                TextField("Descripcion (opcional)", text: $description)

                if isAdvancedMode {
                    Picker("Categoria (opcional)", selection: $category) {
                        ForEach(TransactionCategory.allCases) { category in
                            Text("\(category.emoji) \(category.rawValue)").tag(category)
                        }
                    }

                    TextField("Etiquetas (ej. #cine #viaje)", text: $tagsText)
                        .autocapitalization(.none)

                    Picker("Moneda del pago", selection: $selectedCurrency) {
                        ForEach(ExchangeRateService.commonCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    if isForeignCurrency, let accountCurrency = selectedAccount?.currency {
                        Text("Se convierte de \(selectedCurrency) a \(accountCurrency) al guardar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nuevo movimiento")
            .onAppear {
                selectedAccountId = selectedAccountId ?? accounts.first?.id
                selectedCurrency = selectedAccount?.currency ?? "USD"
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(selectedAccountId == nil || amountText.isEmpty || isSaving || isConverting)
                }
            }
            .overlay {
                if showingSavingAnimation {
                    MovementSavingOverlay(
                        movementType: movementType,
                        itemEmoji: category.emoji,
                        description: description.isEmpty ? category.rawValue : description,
                        amount: enteredMagnitude
                    )
                }
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let accountId = selectedAccountId,
            let magnitude = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        else { return }

        var convertedMagnitude = magnitude
        var originalCurrency: String?
        var originalAmount: Decimal?

        if isAdvancedMode, isForeignCurrency, let accountCurrency = selectedAccount?.currency {
            isConverting = true
            do {
                let result = try await ExchangeRateService.convert(
                    amount: magnitude,
                    from: selectedCurrency,
                    to: accountCurrency
                )
                convertedMagnitude = Decimal(result.convertedAmount)
                originalCurrency = selectedCurrency
                originalAmount = magnitude
            } catch {
                isConverting = false
                errorMessage = "No se pudo convertir \(selectedCurrency) a \(accountCurrency): \(error.localizedDescription)"
                return
            }
            isConverting = false
        }

        isSaving = true
        showingSavingAnimation = true
        defer { isSaving = false }

        do {
            async let saved: Void = viewModel.addTransaction(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: movementType.signedAmount(from: convertedMagnitude),
                    movementType: movementType,
                    category: isAdvancedMode ? category.rawValue : nil,
                    description: description.isEmpty ? nil : description,
                    tags: isAdvancedMode ? parsedTags : [],
                    originalCurrency: originalCurrency,
                    originalAmount: originalAmount,
                    occurredAt: Date()
                )
            )
            async let minDelay: Void = Task.sleep(nanoseconds: MovementSavingOverlay.minDisplayNanoseconds(for: movementType))
            _ = try await (saved, minDelay)
            dismiss()
        } catch {
            showingSavingAnimation = false
            errorMessage = error.localizedDescription
        }
    }
}
