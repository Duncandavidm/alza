import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DashboardViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAccountId: UUID?
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var category: TransactionCategory = .other
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Cuenta", selection: $selectedAccountId) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                Picker("Tipo", selection: $isExpense) {
                    Text("Gasto").tag(true)
                    Text("Ingreso").tag(false)
                }
                .pickerStyle(.segmented)

                TextField("Monto", text: $amountText)
                    .keyboardType(.decimalPad)

                Picker("Categoria", selection: $category) {
                    ForEach(TransactionCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }

                TextField("Descripcion (opcional)", text: $description)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nuevo movimiento")
            .onAppear { selectedAccountId = selectedAccountId ?? accounts.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(selectedAccountId == nil || amountText.isEmpty || isSaving)
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

        let signedAmount = isExpense ? -abs(magnitude) : abs(magnitude)
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.addTransaction(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: signedAmount,
                    category: category.rawValue,
                    description: description.isEmpty ? nil : description,
                    occurredAt: Date()
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
