import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var balanceText = ""
    @State private var isLocked = false
    @State private var availableOn = SavingsAvailability.suggestedDate()
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Tipo tarjeta de credito: cupo, usado, tasa, minimo y dia de pago.
    @State private var card = CreditCardFieldsDraft()

    private var canSave: Bool {
        guard !name.isEmpty, !isSaving else { return false }
        // Una tarjeta necesita su cupo: con eso queda como tarjeta real (disponible y % usado).
        return type == .creditCard ? (card.limit ?? 0) > 0 && (card.used ?? -1) >= 0 : true
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(type == .creditCard ? "Nombre (ej. Visa Banco General)" : "Nombre (ej. BBVA cheques)", text: $name)

                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                if type == .creditCard {
                    CreditCardFieldsSections(draft: $card)
                } else {
                    TextField("Balance actual", text: $balanceText)
                        .keyboardType(.decimalPad)
                }

                if type.isReserve {
                    Toggle("El dinero está bloqueado hasta una fecha", isOn: $isLocked)
                    if isLocked {
                        DatePicker("Disponible desde", selection: $availableOn, displayedComponents: .date)
                        Text("Ese día te preguntamos si ya está disponible y te ayudamos a pasarlo a otra cuenta.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        let balance = AppCountry.parseAmount(balanceText) ?? 0
        isSaving = true
        defer { isSaving = false }

        if type == .creditCard {
            await saveCard(userId: userId)
            return
        }

        do {
            try await viewModel.addAccount(
                NewAccount(
                    userId: userId, name: name, type: type, balance: balance, currency: AppCountry.current.currencyCode,
                    availableOn: type.isReserve && isLocked ? SavingsAvailability.string(from: availableOn) : nil
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Una tarjeta se guarda como deuda con su cupo y tasa; la base le crea
    /// sola su cuenta (saldo en negativo = lo que se debe) y las mantiene
    /// sincronizadas (trigger de 0079).
    private func saveCard(userId: UUID) async {
        guard let used = card.used else { return }
        let paymentDay = card.hasPaymentDay ? card.paymentDay : nil
        do {
            try await SupabaseManager.shared.client
                .from("debts")
                .insert(NewDebt(
                    userId: userId,
                    creditor: name.trimmingCharacters(in: .whitespaces),
                    balance: used,
                    creditLimit: card.limit.flatMap { $0 > 0 ? $0 : nil },
                    interestRateMonthly: card.monthlyRate,
                    minimumPayment: card.minimum,
                    dueDate: paymentDay.flatMap { CreditCardSchedule.nextDueDate(paymentDay: $0) }.map { InvoiceDateFormat.string(from: $0) },
                    isOverdue: false,
                    paymentDay: paymentDay
                ))
                .execute()
            await viewModel.refresh(userId: userId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
