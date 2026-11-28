import SwiftUI

struct AddBudgetView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: BudgetsViewModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var userCategories = UserCategoriesStore.shared
    /// Lo que se guarda en budgets.category: el nombre de una categoria fija
    /// o de una propia (las de Ajustes > Categorías).
    @State private var category: String = TransactionCategory.food.rawValue
    @State private var period: BudgetPeriod = .monthly
    @State private var limitText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Categoría", selection: $category) {
                        ForEach(TransactionCategory.allCases) { category in
                            Text("\(category.emoji) \(category.displayName)").tag(category.rawValue)
                        }
                        ForEach(userCategories.applicable(isInflow: false)) { custom in
                            Text("\(custom.emoji) \(custom.name)").tag(custom.name)
                        }
                    }
                } footer: {
                    Text("¿No está la que necesitas? Crea categorías propias en Ajustes > Categorías.")
                }

                Picker("Periodo", selection: $period) {
                    ForEach(BudgetPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Límite", text: $limitText)
                    .keyboardType(.decimalPad)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nuevo presupuesto")
            .task { await UserCategoriesStore.shared.refresh() }
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
            let limit = AppCountry.parseAmount(limitText)
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.addBudget(
                NewBudget(userId: userId, category: category, period: period, limitAmount: limit)
            )
            dismiss()
        } catch {
            errorMessage = "Ya existe un presupuesto \(period.displayName.lowercased()) para esta categoría, o algo salió mal."
        }
    }
}
