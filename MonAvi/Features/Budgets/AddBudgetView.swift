import SwiftUI

struct AddBudgetView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: BudgetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var category: TransactionCategory = .food
    @State private var period: BudgetPeriod = .monthly
    @State private var limitText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Categoria", selection: $category) {
                    ForEach(TransactionCategory.allCases) { category in
                        Text("\(category.emoji) \(category.rawValue)").tag(category)
                    }
                }

                Picker("Periodo", selection: $period) {
                    ForEach(BudgetPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Limite", text: $limitText)
                    .keyboardType(.decimalPad)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nuevo presupuesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(limitText.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let limit = Decimal(string: limitText.replacingOccurrences(of: ",", with: "."))
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.addBudget(
                NewBudget(userId: userId, category: category.rawValue, period: period, limitAmount: limit)
            )
            dismiss()
        } catch {
            errorMessage = "Ya existe un presupuesto \(period.displayName.lowercased()) para esta categoria, o algo salio mal."
        }
    }
}
