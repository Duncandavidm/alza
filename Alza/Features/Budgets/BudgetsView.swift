import SwiftUI

struct BudgetsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BudgetsViewModel()
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.progresses.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Sin presupuestos todavia",
                        systemImage: "chart.bar.fill",
                        description: Text("Ponle un limite semanal o mensual a una categoria para no pasarte.")
                    )
                }

                ForEach(viewModel.progresses) { progress in
                    budgetRow(progress)
                }
                .onDelete { indexSet in
                    Task { await delete(at: indexSet) }
                }
            }
            .navigationTitle("Presupuestos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .sheet(isPresented: $isAdding) {
                AddBudgetView(viewModel: viewModel)
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func budgetRow(_ progress: BudgetProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(TransactionCategory(rawValue: progress.budget.category)?.emoji ?? "🛍️")
                Text(progress.budget.category)
                    .font(.headline)
                Spacer()
                Text(progress.budget.period.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(progress.ratio, 1))
                .tint(statusColor(progress.status))

            HStack {
                Text("\(progress.spent, format: .currency(code: "USD")) de \(progress.budget.limitAmount, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                switch progress.status {
                case .over:
                    Text("Te pasaste").font(.caption.bold()).foregroundStyle(.red)
                case .warning:
                    Text("Cuidado").font(.caption.bold()).foregroundStyle(.orange)
                case .onTrack:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: BudgetProgress.Status) -> Color {
        switch status {
        case .onTrack: return .green
        case .warning: return .orange
        case .over: return .red
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func delete(at indexSet: IndexSet) async {
        for index in indexSet {
            let progress = viewModel.progresses[index]
            try? await viewModel.deleteBudget(progress.budget)
        }
    }
}
