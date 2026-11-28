import SwiftUI

/// Nueva deuda o editar una existente (tarjeta, prestamo, sobregiro). En
/// una tarjeta: cupo, usado, disponible, tasa al año o al mes, pago minimo
/// y dia de pago.
struct AddDebtView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DebtsViewModel
    /// Si no es nil, se edita esta deuda en vez de crear una.
    var existing: Debt? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var creditor = ""
    @State private var card = CreditCardFieldsDraft()
    @State private var isOverdue = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var isValid: Bool {
        !creditor.trimmingCharacters(in: .whitespaces).isEmpty && (card.used ?? -1) >= 0
    }

    var body: some View {
        Form {
            Section("Deuda") {
                TextField("Nombre (ej. Visa Banco General)", text: $creditor)
            }

            CreditCardFieldsSections(draft: $card, limitIsOptional: true)

            Section {
                Toggle("Está en mora / atrasada", isOn: $isOverdue)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(existing == nil ? "Nueva deuda" : "Editar deuda")
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Guardar") }
                }
                .disabled(!isValid || isSaving)
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        creditor = existing.creditor
        card = CreditCardFieldsDraft(debt: existing)
        isOverdue = existing.isOverdue
    }

    private func save() async {
        guard let userId = appState.currentUserId, let used = card.used else { return }
        isSaving = true
        defer { isSaving = false }
        let paymentDay = card.hasPaymentDay ? card.paymentDay : nil
        let dueDate = paymentDay.flatMap { CreditCardSchedule.nextDueDate(paymentDay: $0) }.map { InvoiceDateFormat.string(from: $0) }
        let limit = card.limit.flatMap { $0 > 0 ? $0 : nil }
        do {
            if let existing {
                try await viewModel.update(
                    existing,
                    creditor: creditor.trimmingCharacters(in: .whitespaces),
                    balance: used,
                    creditLimit: limit,
                    interestRateMonthly: card.monthlyRate,
                    minimumPayment: card.minimum,
                    paymentDay: paymentDay,
                    dueDate: dueDate,
                    isOverdue: isOverdue
                )
            } else {
                try await viewModel.add(
                    NewDebt(
                        userId: userId,
                        creditor: creditor.trimmingCharacters(in: .whitespaces),
                        balance: used,
                        creditLimit: limit,
                        interestRateMonthly: card.monthlyRate,
                        minimumPayment: card.minimum,
                        dueDate: dueDate,
                        isOverdue: isOverdue,
                        paymentDay: paymentDay
                    )
                )
            }
            dismiss()
        } catch {
            errorMessage = L("No se pudo guardar: %@", "\(error.localizedDescription)")
        }
    }
}
