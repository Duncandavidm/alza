import SwiftUI
import Supabase

/// Pagar una tarjeta o deuda: elegir la deuda, de qué cuenta sale el dinero
/// y cuánto (mínimo, total u otro monto). Se abre desde Hoy (botón de pago
/// de deuda o "Vence tu tarjeta"), desde Deudas y desde el aviso del día de
/// pago. En una tarjeta con su cuenta, el pago es una transferencia: sale
/// de la cuenta elegida y baja la deuda de la tarjeta (no cuenta como gasto
/// nuevo; las compras ya se contaron al hacerlas).
struct QuickDebtPaymentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DebtsViewModel()
    /// Vacío = las carga ella misma (al abrirse desde una notificación).
    var accounts: [Account] = []
    var preselectedDebtId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var loadedAccounts: [Account] = []
    @State private var selectedDebtId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var activeDebts: [Debt] {
        viewModel.debts.filter { $0.status != .paidOff }
    }

    private var selectedDebt: Debt? { activeDebts.first { $0.id == selectedDebtId } }

    /// No se paga una tarjeta con otra tarjeta: solo cuentas con dinero.
    private var sourceAccounts: [Account] {
        (accounts.isEmpty ? loadedAccounts : accounts).filter { !$0.type.isLiability }
    }

    private var amount: Decimal { RecurringAmountParser.parse(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                if activeDebts.isEmpty && !viewModel.isLoading {
                    Text("No tienes deudas activas registradas.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        Picker(selectedDebt?.isCard == true ? "Tarjeta" : "Deuda", selection: $selectedDebtId) {
                            ForEach(activeDebts) { debt in
                                Text(debt.creditor).tag(Optional(debt.id))
                            }
                        }
                        if let debt = selectedDebt {
                            LabeledContent("Debes", value: debt.balance.formatted(.currency(code: "USD")))
                            if let limit = debt.creditLimit, limit > 0, let available = debt.availableCredit {
                                LabeledContent("Cupo disponible", value: "\(available.formatted(.currency(code: "USD"))) de \(limit.formatted(.currency(code: "USD")))")
                            }
                            if let day = debt.paymentDay {
                                LabeledContent("Vence", value: "el día \(day) de cada mes")
                            }
                        }
                    }

                    Section("¿Cuánto pagas?") {
                        if let debt = selectedDebt {
                            HStack(spacing: 8) {
                                quickAmount("Mínimo", debt.estimatedMinimum)
                                quickAmount("Todo", debt.balance)
                            }
                            .buttonStyle(.bordered)
                        }
                        AmountField(placeholder: "Monto del pago", text: $amountText)
                        if let debt = selectedDebt, amount > 0, amount < debt.estimatedMinimum {
                            Text("Es menos que el mínimo: puede generar recargos e intereses de mora.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section {
                        Picker("Sale de", selection: $selectedAccountId) {
                            ForEach(sourceAccounts) { account in
                                Text("\(account.name) · \(account.balance.formatted(.currency(code: account.currency)))")
                                    .tag(Optional(account.id))
                            }
                        }
                    } header: {
                        Text("¿De dónde sale el dinero?")
                    } footer: {
                        Text("El pago baja de esa cuenta y reduce lo que debes. No cuenta como gasto nuevo: lo que compraste con la tarjeta ya se contó.")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
            .navigationTitle(selectedDebt?.isCard == true ? "Pagar tarjeta" : "Pago de deuda")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar pago") { Task { await save() } }
                        .disabled(amount <= 0 || selectedDebtId == nil || selectedAccountId == nil || isSaving)
                }
            }
            .task { await load() }
        }
    }

    private func quickAmount(_ label: String, _ value: Decimal) -> some View {
        Button {
            amountText = NSDecimalNumber(decimal: value.roundedTo(2)).stringValue
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.caption)
                Text(value.formatted(.currency(code: "USD"))).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        if accounts.isEmpty {
            loadedAccounts = (try? await SupabaseManager.shared.client
                .from("accounts")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value) ?? []
        }
        selectedDebtId = selectedDebtId
            ?? activeDebts.first { $0.id == preselectedDebtId }?.id
            ?? activeDebts.first?.id
        selectedAccountId = selectedAccountId
            ?? sourceAccounts.first { !$0.type.isReserve }?.id
            ?? sourceAccounts.first?.id
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
                amount: min(amount, debt.balance),
                accountId: accountId,
                creditor: debt.creditor,
                userId: userId
            )
            NotificationCenter.default.post(name: .recurringLoggedFromNotification, object: nil)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
