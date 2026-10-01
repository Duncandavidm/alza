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
    @State private var dueDate = Date()
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
                    Text("Interes mensual (%)")
                    Spacer()
                    TextField("0.0", text: $interestRateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Pago minimo")
                    Spacer()
                    TextField("0.00", text: $minimumPaymentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Tiene fecha de pago", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Fecha de pago", selection: $dueDate, displayedComponents: .date)
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
                        try? await viewModel.add(
                            NewDebt(
                                userId: userId,
                                creditor: creditor,
                                balance: balance,
                                creditLimit: Decimal(string: creditLimitText.replacingOccurrences(of: ",", with: ".")),
                                interestRateMonthly: Decimal(string: interestRateText.replacingOccurrences(of: ",", with: ".")),
                                minimumPayment: Decimal(string: minimumPaymentText.replacingOccurrences(of: ",", with: ".")),
                                dueDate: hasDueDate ? InvoiceDateFormat.string(from: dueDate) : nil,
                                isOverdue: isOverdue
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
