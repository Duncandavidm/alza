import SwiftUI

struct BudgetsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BudgetsViewModel()
    @State private var isAdding = false
    @State private var selectedProgress: BudgetProgress?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.progresses.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Sin presupuestos todavía",
                        systemImage: "chart.bar.fill",
                        description: Text("Ponle un límite semanal o mensual a una categoría para no pasarte.")
                    )
                }

                ForEach(Array(viewModel.progresses.enumerated()), id: \.element.id) { index, progress in
                    budgetRow(progress)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedProgress = progress }
                        .listRowBackground(
                            BudgetColorPalette.color(for: progress.budget, index: index).opacity(0.14)
                        )
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
                    .accessibilityLabel("Agregar presupuesto")
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .sheet(isPresented: $isAdding) {
                AddBudgetView(viewModel: viewModel)
            }
            .sheet(item: $selectedProgress) { progress in
                BudgetDetailSheet(viewModel: viewModel, progress: progress)
            }
            .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
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
                Text(CategoryDisplay.emoji(for: progress.budget.category) ?? "🛍️")
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
                Text("\(progress.spent, format: .appCurrency) de \(progress.budget.limitAmount, format: .appCurrency)")
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
