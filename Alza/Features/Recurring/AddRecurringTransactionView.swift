import SwiftUI

struct AddRecurringTransactionView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: RecurringTransactionsViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountText = ""
    @State private var movementType: MovementType = .gasto
    @State private var category: TransactionCategory = .other
    @State private var dayOfMonth = 1
    @State private var selectedAccountId: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (ej. Netflix, Alquiler)", text: $name)

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

                Picker("Categoria (opcional)", selection: $category) {
                    ForEach(TransactionCategory.allCases) { category in
                        Text("\(category.emoji) \(category.rawValue)").tag(category)
                    }
                }

                Stepper("Dia del mes: \(dayOfMonth)", value: $dayOfMonth, in: 1...28)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva recurrente")
            .onAppear { selectedAccountId = selectedAccountId ?? accounts.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty || amountText.isEmpty || selectedAccountId == nil || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let accountId = selectedAccountId,
            let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.add(
                NewRecurringTransaction(
                    userId: userId,
                    accountId: accountId,
                    name: name,
                    amount: amount,
                    movementType: movementType,
                    category: category.rawValue,
                    dayOfMonth: dayOfMonth
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
