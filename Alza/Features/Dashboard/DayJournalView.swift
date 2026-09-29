import SwiftUI

/// "Mi cuaderno del dia" (mejora #1): todo lo que paso hoy, en el orden en
/// que se anoto — como pasar el lapiz por la libreta al final del dia.
struct DayJournalView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DayJournalViewModel()
    @State private var isQuickAdding = false
    @State private var daySummary: DaySummary?
    @State private var isClosingDay = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    liveTotalBanner

                    List {
                        if viewModel.todayTransactions.isEmpty && !viewModel.isLoading {
                            Text("Todavia no has anotado nada hoy. Toca el + para empezar.")
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                        }

                        ForEach(viewModel.todayTransactions) { transaction in
                            journalRow(transaction)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await refresh() }
                }

                Button {
                    isQuickAdding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(radius: 6, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Hoy")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await closeDay() }
                    } label: {
                        if isClosingDay {
                            ProgressView()
                        } else {
                            Text("Cerrar el dia")
                        }
                    }
                    .disabled(isClosingDay || viewModel.todayTransactions.isEmpty)
                }
            }
            .task { await refresh() }
            .sheet(isPresented: $isQuickAdding) {
                QuickAddView(viewModel: viewModel)
            }
            .sheet(item: $daySummary) { summary in
                DayCloseSummaryView(summary: summary)
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var liveTotalBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hoy llevas")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("+\(viewModel.todayIncome, format: .currency(code: "USD")) ingresos")
                    .foregroundStyle(.green)
                Text("—")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.todayExpense, format: .currency(code: "USD")) gastos")
                    .foregroundStyle(.red)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 4) {
                Text("=")
                    .foregroundStyle(.secondary)
                Text(viewModel.todayNet, format: .currency(code: "USD"))
                    .foregroundStyle(viewModel.todayNet >= 0 ? .green : .red)
                Text("en tu bolsillo")
                    .foregroundStyle(.secondary)
            }
            .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func journalRow(_ transaction: FinanceTransaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(transaction.movementType.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description ?? transaction.movementType.displayName)
                    .font(.body)
                Text(transaction.occurredAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: "USD"))
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.movementType.tintColor)
        }
        .padding(.vertical, 4)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func closeDay() async {
        guard let userId = appState.currentUserId else { return }
        isClosingDay = true
        defer { isClosingDay = false }
        daySummary = await viewModel.closeDaySummary(userId: userId)
    }
}

extension DaySummary: Identifiable {
    var id: String { "\(income)-\(expense)-\(mood.title)" }
}
