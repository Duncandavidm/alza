import SwiftUI

struct AddDebtView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DebtsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var creditor = ""
    @State private var balanceText = ""
    @State private var creditLimitText = ""
    @State private var interestRateText = ""
    @State private var minimumPaymentText = ""
    @State private var hasDueDate = false
    /// Dia del mes en que vence (tarjetas y prestamos se pagan cada mes).
    @State private var paymentDay = 15
    @State private var isOverdue = false
    @State private var isSaving = false

    private var balance: Decimal? { Decimal(string: balanceText.replacingOccurrences(of: ",", with: ".")) }

    private var isValid: Bool {
        !creditor.trimmingCharacters(in: .whitespaces).isEmpty && (balance ?? 0) >= 0 && balance != nil
    }

    var body: some View {
        Form {
            Section("Deuda") {
                TextField("Acreedor (ej. Tarjeta Banco General)", text: $creditor)
                HStack {
                    Text("Saldo actual")
                    Spacer()
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Cupo (opcional)")
                    Spacer()
                    TextField("0.00", text: $creditLimitText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Pago") {
                HStack {
                    Text("Interés mensual (%)")
                    Spacer()
                    TextField("0.0", text: $interestRateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Pago mínimo")
                    Spacer()
                    TextField("0.00", text: $minimumPaymentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Se paga cada mes", isOn: $hasDueDate)
                if hasDueDate {
                    DayOfMonthField(label: "Día de pago", day: $paymentDay)
                    Text("Te avisamos 3 días antes y el mismo día, y registras de qué cuenta salió el pago.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Esta en mora / atrasada", isOn: $isOverdue)
            }
        }
        .navigationTitle("Nueva deuda")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    guard let userId = appState.currentUserId, let balance else { return }
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        _ = try? await viewModel.add(
                            NewDebt(
                                userId: userId,
                                creditor: creditor,
                                balance: balance,
                                creditLimit: Decimal(string: creditLimitText.replacingOccurrences(of: ",", with: ".")),
                                interestRateMonthly: Decimal(string: interestRateText.replacingOccurrences(of: ",", with: ".")),
                                minimumPayment: Decimal(string: minimumPaymentText.replacingOccurrences(of: ",", with: ".")),
                                dueDate: hasDueDate
                                    ? CreditCardSchedule.nextDueDate(paymentDay: paymentDay).map { InvoiceDateFormat.string(from: $0) }
                                    : nil,
                                isOverdue: isOverdue,
                                paymentDay: hasDueDate ? paymentDay : nil
                            )
                        )
                        dismiss()
                    }
                } label: {
                    if isSaving { ProgressView() } else { Text("Guardar") }
                }
                .disabled(!isValid || isSaving)
            }
        }
    }
}
