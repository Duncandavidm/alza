import SwiftUI

/// Acceso rapido desde el dashboard (FAB) para aportar a una meta de
/// ahorro sin tener que ir hasta Ajustes > Metas de ahorro — solo elegir
/// la meta y el monto.
struct QuickSavingsContributionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SavingsGoalsViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoalId: UUID?
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var openGoals: [SavingsGoal] {
        viewModel.goals.filter { !$0.isAchieved }
    }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if openGoals.isEmpty && !viewModel.isLoading {
                    Text("No tienes metas de ahorro pendientes. Crea una en Ajustes > Metas de ahorro.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Meta", selection: $selectedGoalId) {
                        ForEach(openGoals) { goal in
                            Text("\(goal.emoji) \(goal.name)").tag(Optional(goal.id))
                        }
                    }

                    AmountField(placeholder: "Monto del aporte", text: $amountText)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
            .navigationTitle("Aportar a meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(amount <= 0 || selectedGoalId == nil || isSaving)
                }
            }
            .task {
                guard let userId = appState.currentUserId else { return }
                await viewModel.refresh(userId: userId)
                selectedGoalId = openGoals.first?.id
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let goalId = selectedGoalId,
            let goal = openGoals.first(where: { $0.id == goalId })
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.contribute(to: goal, amount: amount, userId: userId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
