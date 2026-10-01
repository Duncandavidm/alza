import SwiftUI

/// "Mi cuaderno del dia" (mejora #1): todo lo que paso hoy, en el orden en
/// que se anoto — como pasar el lapiz por la libreta al final del dia.
struct DayJournalView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DayJournalViewModel()
    @StateObject private var budgetsViewModel = BudgetsViewModel()
    @StateObject private var recurringViewModel = RecurringTransactionsViewModel()
    @StateObject private var billsViewModel = BillsViewModel()
    @State private var isQuickAdding = false
    @State private var daySummary: DaySummary?
    @State private var isClosingDay = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    liveTotalBanner

                    if appState.subscriptionStatus.isEntitled && appState.subscriptionStore.willAutoRenew == false {
                        cancellationBanner
                    }

                    if !billsViewModel.pending.isEmpty {
                        billsStrip
                    }

                    if !budgetsViewModel.progresses.isEmpty {
                        budgetsStrip
                    }

                    ForEach(recurringViewModel.dueToday) { item in
                        recurringReminderRow(item)
                    }

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
                    .refreshable {
                        await refresh()
                        await refreshBudgets()
                    }
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
                .pressable()
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
            .task { await refreshBudgets() }
            .task { await refreshRecurring() }
            .task { await refreshBills() }
            .task { await appState.subscriptionStore.refreshRenewalInfo() }
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

    /// El cliente cancelo la suscripcion (desde Ajustes de iOS o el sheet de
    /// "Administrar suscripcion", algo que pasa fuera de la app) pero sigue
    /// con acceso hasta que termine el periodo ya pagado — Apple nunca
    /// corta el acceso a mitad de un periodo pagado. Esto tiene que
    /// verselo el cliente aqui, no quedar escondido en Ajustes.
    private var cancellationBanner: some View {
        Button {
            Task { await appState.subscriptionStore.openManageSubscriptions() }
        } label: {
            HStack(spacing: 10) {
                Text("⏳")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu suscripcion no se va a renovar")
                        .font(.subheadline.weight(.medium))
                    if let endDate = appState.subscriptionStore.currentPeriodEndDate {
                        Text("Finaliza el \(endDate.formatted(date: .long, time: .omitted)) — hasta ahi tienes acceso completo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .foregroundStyle(.primary)
        }
        .background(AlzaBrand.alert.opacity(0.12))
    }

    /// Cuentas por pagar pendientes, mas cercanas primero — el diferenciador
    /// de Alza necesita ser visible aqui, no escondido en Ajustes.
    private var billsStrip: some View {
        NavigationLink {
            BillsView()
        } label: {
            HStack(spacing: 10) {
                Text("🧾")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(billsViewModel.pending.count) cuenta(s) por pagar")
                        .font(.subheadline.weight(.medium))
                    if let next = billsViewModel.pending.first {
                        Text("\(next.name) — \(next.dueDateValue.formatted(date: .abbreviated, time: .omitted))\(next.isOverdue ? " (vencida)" : "")")
                            .font(.caption)
                            .foregroundStyle(next.isOverdue ? .red : .secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .foregroundStyle(.primary)
        }
        .background(Color(.secondarySystemBackground))
    }

    /// Progreso de presupuestos, visible "justo en la pantalla principal"
    /// (inspirado en MonAi) en vez de escondido en un reporte aparte.
    private var budgetsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(budgetsViewModel.progresses) { progress in
                    BudgetProgressChip(progress: progress)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    /// "¿Pagaste el Gimnasio hoy?" — recordatorio de una recurrente que le
    /// toca hoy y todavia no se ha confirmado este mes.
    @ViewBuilder
    private func recurringReminderRow(_ item: RecurringTransaction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("⚠️")
                Text("¿Pagaste \(item.name) hoy? \(item.amount, format: .currency(code: "USD"))")
                    .font(.subheadline)
                Spacer()
            }
            HStack(spacing: 10) {
                Button("Si, lo pague") {
                    Task { await confirmRecurring(item) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Recordarme despues") {
                    recurringViewModel.dismissReminder(for: item)
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
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

    private func refreshBudgets() async {
        guard let userId = appState.currentUserId else { return }
        await budgetsViewModel.refresh(userId: userId)
    }

    private func refreshRecurring() async {
        guard let userId = appState.currentUserId else { return }
        await recurringViewModel.refresh(userId: userId)
    }

    private func refreshBills() async {
        guard let userId = appState.currentUserId else { return }
        await billsViewModel.refresh(userId: userId)
    }

    private func confirmRecurring(_ item: RecurringTransaction) async {
        guard let userId = appState.currentUserId else { return }
        try? await recurringViewModel.confirmPayment(for: item, userId: userId)
        await refresh()
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
