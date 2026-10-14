import SwiftUI

/// Acceso rapido desde el dashboard (FAB) para abonar a una deuda sin
/// tener que ir hasta Ajustes > Deudas — solo elegir la deuda, la cuenta
/// de origen y el monto.
struct QuickDebtPaymentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DebtsViewModel()
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDebtId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var activeDebts: [Debt] {
        viewModel.debts.filter { $0.status != .paidOff }
    }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if activeDebts.isEmpty && !viewModel.isLoading {
                    Text("No tienes deudas activas registradas.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Deuda", selection: $selectedDebtId) {
                        ForEach(activeDebts) { debt in
                            Text("\(debt.creditor) — \(debt.balance, format: .currency(code: "USD"))")
                                .tag(Optional(debt.id))
                        }
                    }

                    Picker("Cuenta de origen", selection: $selectedAccountId) {
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }

                    AmountField(placeholder: "Monto del pago", text: $amountText)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
            .navigationTitle("Pago de deuda")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(amount <= 0 || selectedDebtId == nil || selectedAccountId == nil || isSaving)
                }
            }
            .task {
                guard let userId = appState.currentUserId else { return }
                await viewModel.refresh(userId: userId)
                selectedDebtId = activeDebts.first?.id
                selectedAccountId = accounts.first?.id
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let debtId = selectedDebtId,
            let accountId = selectedAccountId,
            let debt = activeDebts.first(where: { $0.id == debtId })
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await PaymentAdviceActions.payDebt(
                debtId: debtId,
                amount: amount,
                accountId: accountId,
                creditor: debt.creditor,
                userId: userId
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
