import SwiftUI

/// Lista de metas de ahorro con barra de progreso y la cuota mensual
/// sugerida por fila — el numero que el cliente pidio ver de un vistazo.
struct SavingsGoalsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SavingsGoalsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isAdding = false
    @State private var editingGoal: SavingsGoal?
    @State private var contributingGoal: SavingsGoal?

    var body: some View {
        List {
            if viewModel.goals.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin metas de ahorro",
                    systemImage: "target",
                    description: Text("Crea una meta — un carro, un TV, un viaje — y MonAvi te dice cuánto ahorrar cada mes para llegar a tiempo.")
                )
            }

            ForEach(viewModel.goals) { goal in
                goalRow(goal)
                    .contentShape(Rectangle())
                    .onTapGesture { editingGoal = goal }
            }
            .onDelete { indexSet in
                Task { await delete(at: indexSet) }
            }
        }
        .navigationTitle("Metas de ahorro")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Agregar meta de ahorro")
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $isAdding) {
            AddSavingsGoalView(viewModel: viewModel, accounts: accountsViewModel.accounts)
        }
        .sheet(item: $editingGoal) { goal in
            AddSavingsGoalView(viewModel: viewModel, accounts: accountsViewModel.accounts, existingGoal: goal)
        }
        .sheet(item: $contributingGoal) { goal in
            ContributeToGoalView(viewModel: viewModel, goal: goal)
        }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func goalRow(_ goal: SavingsGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).font(.body)
                    Text(goal.targetDateValue.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))
                        .font(.caption)
                        .foregroundStyle(goal.isPastDue ? MonAviBrand.alert : .secondary)
                }

                Spacer()

                Button {
                    contributingGoal = goal
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MonAviBrand.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abonar a la meta")
                .disabled(goal.isAchieved)
            }

            ProgressView(value: goal.progress)
                .tint(goal.isAchieved ? .green : MonAviBrand.primary)

            HStack {
                Text("\(goal.currentAmount, format: .currency(code: "USD")) de \(goal.targetAmount, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if goal.isAchieved {
                    Text("¡Meta cumplida! 🎉")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else {
                    Text("\(goal.monthlyContributionNeeded, format: .currency(code: "USD"))/mes")
                        .font(.caption.bold())
                        .foregroundStyle(MonAviBrand.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        await accountsViewModel.refresh(userId: userId)
    }

    private func delete(at indexSet: IndexSet) async {
        for index in indexSet {
            try? await viewModel.delete(viewModel.goals[index])
        }
    }
}

/// Hoja chica para registrar un aporte o un retiro — monto y listo, sin
/// tocar nombre/fecha.
private struct ContributeToGoalView: View {
    enum Mode: Hashable { case deposit, withdraw }

    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: SavingsGoalsViewModel
    let goal: SavingsGoal
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .deposit
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $mode) {
                        Text("Aportar").tag(Mode.deposit)
                        Text("Retirar").tag(Mode.withdraw)
                    }
                    .pickerStyle(.segmented)
                    .disabled(goal.currentAmount <= 0)

                    AmountField(
                        placeholder: mode == .deposit ? "Monto del aporte" : "Monto a retirar",
                        text: $amountText
                    )
                } header: {
                    Text("\(goal.emoji) \(goal.name) — llevas \(goal.currentAmount, format: .currency(code: "USD"))")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if goal.accountId != nil {
                            Text("Se registrará también como movimiento en la cuenta vinculada.")
                        }
                        if mode == .withdraw {
                            Text("Retirar hace que los aportes de los últimos 30 días de esta meta no cuenten para tu nivel.")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
            .navigationTitle(mode == .deposit ? "Agregar aporte" : "Retirar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(amount <= 0 || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let signed = mode == .deposit ? amount : -amount
            try await viewModel.contribute(to: goal, amount: signed, userId: userId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
