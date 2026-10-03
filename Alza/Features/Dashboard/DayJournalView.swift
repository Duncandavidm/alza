import SwiftUI

/// El dashboard principal — rediseño inspirado en un paywall/dashboard de
/// referencia que le gusto al cliente: numero grande, pastillas de
/// ingreso/gasto, barras "candy" de presupuesto, y accesos rapidos de
/// agregar/buscar/voz abajo. Con los colores de marca de Amadai.
struct DayJournalView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DayJournalViewModel()
    @StateObject private var budgetsViewModel = BudgetsViewModel()
    @StateObject private var recurringViewModel = RecurringTransactionsViewModel()
    @StateObject private var billsViewModel = BillsViewModel()
    @State private var isQuickAdding = false
    @State private var isVoiceQuickAdding = false
    @State private var daySummary: DaySummary?
    @State private var isClosingDay = false
    @State private var isShowingDatePicker = false
    @State private var isSearching = false
    @State private var selectedBudgetProgress: BudgetProgress?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if isSearching {
                            searchField
                        }

                        if appState.subscriptionStatus.isEntitled && appState.subscriptionStore.willAutoRenew == false {
                            cancellationBanner
                        }

                        totalsCard

                        if !budgetsViewModel.progresses.isEmpty {
                            BudgetCandyBarRow(progresses: budgetsViewModel.progresses) { progress in
                                selectedBudgetProgress = progress
                            }
                        }

                        if !billsViewModel.pending.isEmpty {
                            billsStrip
                        }

                        ForEach(recurringViewModel.dueToday) { item in
                            recurringReminderRow(item)
                        }

                        transactionList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await refresh()
                    await refreshBudgets()
                }

                fabRow
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isViewingToday {
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
            }
            .task { await refresh() }
            .task { await refreshBudgets() }
            .task { await refreshRecurring() }
            .task { await refreshBills() }
            .task { await appState.subscriptionStore.refreshRenewalInfo() }
            .sheet(isPresented: $isQuickAdding) {
                QuickAddView(viewModel: viewModel)
            }
            .sheet(isPresented: $isVoiceQuickAdding) {
                QuickAddView(viewModel: viewModel, autoStartVoice: true)
            }
            .sheet(item: $daySummary) { summary in
                DayCloseSummaryView(summary: summary)
            }
            .sheet(item: $selectedBudgetProgress) { progress in
                BudgetDetailSheet(viewModel: budgetsViewModel, progress: progress)
            }
            .sheet(isPresented: $isShowingDatePicker) {
                datePickerSheet
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isViewingToday ? "Hoy" : dateLabel)
                    .font(.system(.title2, design: AmadaiBrand.fontDesign, weight: .bold))
                if !viewModel.isViewingToday {
                    Button("Volver a hoy") {
                        viewModel.selectedDate = Date()
                        Task { await refresh() }
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button {
                isShowingDatePicker = true
            } label: {
                Image(systemName: "calendar")
                    .frame(width: 38, height: 38)
            }
            .background(Circle().fill(Color(.secondarySystemBackground)))

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 38, height: 38)
            }
            .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    private var dateLabel: String {
        viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar o #etiqueta", text: $viewModel.searchQuery)
                .onChange(of: viewModel.searchQuery) {
                    Task { await search() }
                }
            if viewModel.isSearching {
                ProgressView().controlSize(.small)
            } else if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isSearching = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Totales

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if totalOverBudget > 0 {
                Text("\(totalOverBudget, format: .currency(code: "USD")) sobre presupuesto")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmadaiBrand.alert)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: viewModel.todayNet >= 0 ? "plus" : "minus")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(viewModel.todayNet >= 0 ? AmadaiBrand.primary : AmadaiBrand.alert)
                Text(abs(viewModel.todayNet), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 42, weight: .heavy, design: AmadaiBrand.fontDesign))
                Text("$")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            HStack(spacing: 10) {
                pill(icon: "arrow.down", amount: viewModel.todayExpense, color: AmadaiBrand.alert)
                pill(icon: "arrow.up", amount: viewModel.todayIncome, color: AmadaiBrand.primary)
            }
        }
    }

    private var totalOverBudget: Decimal {
        budgetsViewModel.progresses
            .filter { $0.status == .over }
            .reduce(Decimal(0)) { $0 + ($1.spent - $1.budget.limitAmount) }
    }

    private func pill(icon: String, amount: Decimal, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(color))
            Text(amount, format: .currency(code: "USD"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
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
        .background(RoundedRectangle(cornerRadius: 14).fill(AmadaiBrand.alert.opacity(0.12)))
    }

    /// Cuentas por pagar pendientes, mas cercanas primero — el diferenciador
    /// de Amadai necesita ser visible aqui, no escondido en Ajustes.
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
                            .foregroundStyle(next.isOverdue ? AmadaiBrand.alert : .secondary)
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - Lista de movimientos

    @ViewBuilder
    private var transactionList: some View {
        if isSearching, let results = viewModel.searchResults {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(results.count) resultado(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if results.isEmpty && !viewModel.isSearching {
                    Text("Nada por ahi.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(results) { transaction in
                        journalRow(transaction)
                        Divider()
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.todayTransactions.isEmpty && !viewModel.isLoading {
                    Text(viewModel.isViewingToday ? "Todavia no has anotado nada hoy. Toca el + para empezar." : "No hay movimientos ese dia.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(viewModel.todayTransactions) { transaction in
                        journalRow(transaction)
                        Divider()
                    }
                }
            }
        }
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
        .padding(.vertical, 6)
    }

    // MARK: - Accesos rapidos (abajo)

    private var fabRow: some View {
        HStack {
            HStack(spacing: 10) {
                Button {
                    isQuickAdding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
                .background(Circle().fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .pressable()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
                .background(Circle().fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .pressable()
            }
            .foregroundStyle(.primary)

            Spacer()

            Button {
                isVoiceQuickAdding = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(AmadaiBrand.headerGradient))
                    .shadow(color: AmadaiBrand.primary.opacity(0.4), radius: 10, y: 4)
            }
            .pressable()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Elige un dia",
                selection: Binding(
                    get: { viewModel.selectedDate },
                    set: { newValue in
                        viewModel.selectedDate = newValue
                        isShowingDatePicker = false
                        Task { await refresh() }
                    }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Ver otro dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { isShowingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Datos

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func search() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.search(userId: userId)
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
