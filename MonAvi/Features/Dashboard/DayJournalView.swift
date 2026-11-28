import SwiftUI

/// El dashboard principal — rediseño inspirado en un paywall/dashboard de
/// referencia que le gusto al cliente: numero grande, pastillas de
/// ingreso/gasto, barras "candy" de presupuesto, y accesos rapidos de
/// agregar/buscar/voz abajo. Con los colores de marca de MonAvi.
struct DayJournalView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DayJournalViewModel()
    @ObservedObject private var router = NotificationRouter.shared
    /// Avisos del banco detectados por Atajos, por confirmar.
    @ObservedObject private var detectedStore = DetectedMovementStore.shared
    @State private var reviewingDetected: DetectedMovement?
    /// "¿Ya pagaste…?" ocultas con la X: solo por ahora. Al volver a abrir
    /// la app aparecen de nuevo hasta que la persona responda.
    @State private var hiddenForNow: Set<String> = []
    /// Para repintar emojis de categorias propias cuando terminan de cargar.
    @ObservedObject private var userCategories = UserCategoriesStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Dia en que se vio Hoy por ultima vez, para detectar que paso la
    /// medianoche con la app abierta o en segundo plano.
    @State private var lastActiveDay = Calendar.current.startOfDay(for: Date())
    @StateObject private var budgetsViewModel = BudgetsViewModel()
    @StateObject private var recurringViewModel = RecurringTransactionsViewModel()
    @StateObject private var suggestionsModel = RecurringSuggestionsModel()
    @StateObject private var billsViewModel = BillsViewModel()
    @StateObject private var dgiViewModel = DgiReceiptsViewModel()
    @State private var isQuickAdding = false
    @State private var isVoiceQuickAdding = false
    @State private var isRecordingDebtPayment = false
    @State private var isContributingToSavings = false
    @State private var isShowingDgiConsent = false
    @State private var isShowingInvoiceScanner = false
    /// Gasto recien anotado cuya factura se va a escanear (ver openPendingInvoiceForExpense).
    @State private var pendingInvoiceExpense: FinanceTransaction?
    @State private var isAddingBudget = false
    /// El usuario oculto "Tu ahorro" de Hoy (se vuelve a mostrar en Ajustes).
    @AppStorage("monavi.hideSavingsCardInHoy") private var hideSavingsCard = false
    /// El usuario cerro "Crea tu primer presupuesto" (se vuelve a mostrar en Ajustes).
    @AppStorage("monavi.hideBudgetInviteInHoy") private var hideBudgetInvite = false
    @State private var didLoadBudgets = false
    @State private var invoiceExpense: FinanceTransaction?
    @State private var editingTransaction: FinanceTransaction?
    /// Deslizar a la izquierda (o "Eliminar"): se confirma antes de borrar.
    @State private var pendingDeletion: FinanceTransaction?
    /// Tocar un movimiento con factura: aviso de que no se edita.
    @State private var lockedInvoiceTransaction: FinanceTransaction?
    @State private var daySummary: DaySummary?
    @State private var isClosingDay = false
    @State private var isShowingDatePicker = false
    @State private var isSearching = false
    @State private var selectedBudgetProgress: BudgetProgress?
    @State private var pointsByTransaction: [UUID: Int] = [:]
    @State private var activeGiftsCount = 0
    @StateObject private var savingsViewModel = SavingsGoalsViewModel()
    /// "Pasar a otra cuenta" cuando se libera un ahorro bloqueado.
    @State private var transferRequest: AccountTransferRequest?
    /// "Aún no": elegir cuándo estará libre.
    @State private var snoozeAccount: Account?
    @State private var snoozeDate = Date()
    /// "Pagar tarjeta" desde el aviso de vencimiento en Hoy.
    @State private var cardPaymentRequest: CardPaymentRequest?
    /// "Te estás sobreendeudando" / "Gastas más de lo que ganas" (estudio
    /// real, ver FinancialHealthLoader).
    @State private var healthAlert: FinancialSnapshot.Alert?
    /// "Fue otro monto" en el recordatorio de un pago fijo.
    @State private var amountPromptItem: RecurringTransaction?
    @State private var customAmountText = ""
    /// "Sí, otro monto" en un gasto que se repite.
    @State private var otherAmountSuggestion: RecurringDetector.Suggestion?
    @State private var suggestionAmountText = ""
    /// El guardián: movimientos de los ultimos meses para comparar.
    @State private var guardTransactions: [FinanceTransaction] = []
    /// «Anotar el ingreso» desde una alerta del guardián.
    @State private var incomeRequest: IncomeRequest?
    @State private var isShowingSpending = false
    @State private var isShowingBills = false
    /// Tope de ingresos para el cashback y revisión (1.1.0, 0100).
    @State private var incomeStatus: IncomeStatus?
    @State private var isShowingIncomeVerification = false

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

                        if let alert = healthAlert, viewModel.isViewingToday && !isSearching {
                            debtAlertBanner(alert)
                        }

                        if viewModel.isViewingToday && !isSearching {
                            moneyGuardRows
                        }

                        if !viewModel.accounts.isEmpty && !isSearching {
                            accountsStrip
                        }

                        // "Tu ahorro" se puede ocultar con la X (y volver a
                        // mostrar en Ajustes).
                        if !hideSavingsCard && !isSearching {
                            savingsCard
                        }

                        // Presupuestos: siempre a la vista, antes de avisos y movimientos.
                        if !budgetsViewModel.progresses.isEmpty && !isSearching {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tus presupuestos del mes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                BudgetCandyBarRow(progresses: budgetsViewModel.progresses, barHeight: 96) { progress in
                                    selectedBudgetProgress = progress
                                }
                            }
                        } else if didLoadBudgets && !hideBudgetInvite && viewModel.isViewingToday && !isSearching {
                            // Sin presupuestos: el lugar queda para invitar a crear el primero.
                            emptyBudgetsCard
                        }

                        // Avisos del banco (Atajos) que esperan confirmacion.
                        if viewModel.isViewingToday && !isSearching {
                            DetectedMovementsCard(
                                store: detectedStore,
                                onReview: { reviewingDetected = $0 },
                                onQuickRegister: { movement in Task { await quickRegisterDetected(movement) } }
                            )
                        }

                        cardDueRows

                        savingsAvailableRows

                        recurringSuggestionCards

                        if !billsViewModel.pending.isEmpty {
                            billsStrip
                        }

                        ForEach(recurringViewModel.dueToday.filter { !hiddenForNow.contains("r-\($0.id)") }) { item in
                            recurringReminderRow(item)
                                .overlay(alignment: .topTrailing) { hideForNowButton("r-\(item.id)") }
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
                    await refreshFeaturedRewards()
                }
                .alert(amountPromptTitle, isPresented: isAmountPromptShown) {
                    TextField("Monto, ej. \(AppCountry.current.amountExample)", text: $customAmountText)
                        .keyboardType(.decimalPad)
                    Button("Registrar") {
                        if let item = amountPromptItem, let amount = RecurringAmountParser.parse(customAmountText) {
                            Task { await confirmRecurring(item, amount: amount) }
                        }
                        amountPromptItem = nil
                    }
                    Button("Cancelar", role: .cancel) { amountPromptItem = nil }
                } message: {
                    Text("Lo anotamos con este monto solo esta vez. El de siempre sigue igual.")
                }
                .alert("¿Cuánto pagaste de \(otherAmountSuggestion?.name ?? "")?", isPresented: isSuggestionAmountShown) {
                    TextField("Monto, ej. \(AppCountry.current.amountExample)", text: $suggestionAmountText)
                        .keyboardType(.decimalPad)
                    Button("Registrar") {
                        if let suggestion = otherAmountSuggestion, let amount = RecurringAmountParser.parse(suggestionAmountText) {
                            Task { await acceptSuggestion(suggestion, paidAmount: amount) }
                        }
                        otherAmountSuggestion = nil
                    }
                    Button("Cancelar", role: .cancel) { otherAmountSuggestion = nil }
                } message: {
                    Text("Lo anotamos este mes y lo guardamos como gasto fijo para recordártelo.")
                }

                fabRow
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Los premios viven detras de este boton, no en la
                    // pantalla principal: Hoy es para tus gastos y tu ahorro.
                    NavigationLink {
                        PointsHubView()
                    } label: {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(MonAviBrand.primary)
                            .overlay(alignment: .topTrailing) {
                                if activeGiftsCount > 0 {
                                    Circle()
                                        .fill(MonAviBrand.alert)
                                        .frame(width: 9, height: 9)
                                        .offset(x: 4, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel(activeGiftsCount > 0 ? L("Canjear premios. Tienes regalos sin usar") : L("Canjear premios"))
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isViewingToday {
                        Button {
                            Task { await closeDay() }
                        } label: {
                            if isClosingDay {
                                ProgressView()
                            } else {
                                Text("Cerrar el día")
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
            .task { await refreshDgiConsent() }
            .task { await refreshFeaturedRewards() }
            .task { await appState.subscriptionStore.refreshRenewalInfo() }
            .task { await showPreviousDayIfNeeded() }
            .task { await refreshHealthAlert() }
            .sheet(item: $transferRequest, onDismiss: {
                Task { await refresh() }
            }) { request in
                AccountTransferView(sourceAccountId: request.sourceAccountId)
            }
            .sheet(item: $snoozeAccount) { account in
                NavigationStack {
                    Form {
                        Section {
                            DatePicker("Disponible desde", selection: $snoozeDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                        } footer: {
                            Text("Ese día te volvemos a preguntar si ya está disponible el dinero de \(account.name).")
                        }
                    }
                    .navigationTitle("¿Cuándo estará libre?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { snoozeAccount = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Guardar") { Task { await saveSnooze() } }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $cardPaymentRequest, onDismiss: {
                Task {
                    await refresh()
                    await refreshHealthAlert()
                }
            }) { request in
                QuickDebtPaymentView(accounts: viewModel.accounts, preselectedDebtId: request.debtId)
            }
            // "Movimiento detectado" (aviso del banco): revisar antes de guardar.
            .sheet(item: $reviewingDetected) { movement in
                DetectedMovementReviewView(
                    movement: movement,
                    accounts: viewModel.accounts,
                    userId: appState.currentUserId,
                    progresses: budgetsViewModel.progresses,
                    position: (detectedStore.pending.firstIndex { $0.id == movement.id } ?? 0) + 1,
                    total: detectedStore.pending.count
                ) {
                    Task {
                        await refresh()
                        await refreshBudgets()
                        // "1 de 2": al terminar uno se abre el siguiente.
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        if reviewingDetected == nil, let next = detectedStore.pending.first {
                            reviewingDetected = next
                        }
                    }
                }
            }
            .onChange(of: router.detectedMovementToReview) { _, id in
                openDetectedMovement(id)
            }
            .onAppear {
                openDetectedMovement(router.detectedMovementToReview)
                openQuickAddFromWidget(router.quickAddRequestedAt)
            }
            // "+ Agregar" desde el widget "Tu día".
            .onChange(of: router.quickAddRequestedAt) { _, requestedAt in
                openQuickAddFromWidget(requestedAt)
            }
            // "Sí, ya lo pagué" desde la notificacion con la app abierta:
            // el movimiento nuevo y el recordatorio se actualizan solos.
            .onReceive(NotificationCenter.default.publisher(for: .recurringLoggedFromNotification)) { _ in
                Task {
                    await refresh()
                    await refreshRecurring()
                    await refreshHealthAlert()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { hiddenForNow.removeAll() }
                guard phase == .active else { return }
                // Un atajo pudo detectar movimientos con la app en segundo plano.
                detectedStore.load()
                Task { await handleDayChangeIfNeeded() }
            }
            // Al cerrar "Registrar con voz" (Atajo / Tocar atrás) puede haber
            // un movimiento nuevo (o uno deshecho): recargar el dia.
            .onChange(of: router.isVoiceCapturePresented) { _, isPresented in
                guard !isPresented else { return }
                Task {
                    await refresh()
                    await refreshBudgets()
                }
            }
            .sheet(isPresented: $isQuickAdding, onDismiss: openPendingInvoiceForExpense) {
                QuickAddView(viewModel: viewModel, onScanInvoice: { pendingInvoiceExpense = $0 })
            }
            .sheet(isPresented: $isVoiceQuickAdding, onDismiss: openPendingInvoiceForExpense) {
                QuickAddView(viewModel: viewModel, autoStartVoice: true, onScanInvoice: { pendingInvoiceExpense = $0 })
            }
            .sheet(isPresented: $isShowingDgiConsent) {
                DgiConsentView(viewModel: dgiViewModel) {
                    isShowingInvoiceScanner = true
                }
            }
            .sheet(isPresented: $isShowingInvoiceScanner, onDismiss: {
                invoiceExpense = nil
                // La factura se registra como gasto: que aparezca de una vez.
                Task {
                    await refresh()
                    await refreshBudgets()
                }
            }) {
                ScanInvoiceView(viewModel: dgiViewModel, accounts: viewModel.accounts, linkTo: invoiceExpense)
            }
            .sheet(isPresented: $isAddingBudget, onDismiss: {
                Task { await refreshBudgets() }
            }) {
                AddBudgetView(viewModel: budgetsViewModel)
            }
            .sheet(item: $incomeRequest, onDismiss: { Task { await refreshGuard() } }) { request in
                QuickAddView(viewModel: viewModel, initialMovementType: .ingreso, initialAccountId: request.accountId)
            }
            .onChange(of: isQuickAdding) { _, isPresented in
                if !isPresented { Task { await refreshGuard() } }
            }
            .navigationDestination(isPresented: $isShowingSpending) { SpendingInsightsView() }
            .navigationDestination(isPresented: $isShowingBills) { BillsView() }
            .navigationDestination(isPresented: $isShowingIncomeVerification) { IncomeVerificationView() }
            .sheet(item: $editingTransaction) { transaction in
                QuickAddView(viewModel: viewModel, existingTransaction: transaction)
            }
            .confirmationDialog(
                TransactionRowText.deleteTitle,
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { transaction in
                Button("Eliminar", role: .destructive) {
                    Task { await delete(transaction) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { transaction in
                Text(TransactionRowText.deleteMessage(for: transaction))
            }
            .alert(
                TransactionRowText.lockedTitle,
                isPresented: Binding(get: { lockedInvoiceTransaction != nil }, set: { if !$0 { lockedInvoiceTransaction = nil } })
            ) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(TransactionRowText.lockedMessage)
            }
            .sheet(isPresented: $isRecordingDebtPayment) {
                QuickDebtPaymentView(accounts: viewModel.accounts)
            }
            .sheet(isPresented: $isContributingToSavings) {
                QuickSavingsContributionView()
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
            .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
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
                Text(viewModel.isViewingToday ? L("Hoy") : dateLabel)
                    .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
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
            .accessibilityLabel("Ver otro día")

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 38, height: 38)
            }
            .background(Circle().fill(Color(.secondarySystemBackground)))
            .accessibilityLabel("Ajustes")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    private var dateLabel: String {
        viewModel.selectedDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi))
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
                Text("\(totalOverBudget, format: .appCurrency) sobre presupuesto")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MonAviBrand.alert)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: viewModel.todayNet >= 0 ? "plus" : "minus")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(viewModel.todayNet >= 0 ? MonAviBrand.primary : MonAviBrand.alert)
                Text(abs(viewModel.todayNet), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 42, weight: .heavy, design: MonAviBrand.fontDesign))
                Text("$")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            HStack(spacing: 10) {
                pill(icon: "arrow.down", amount: viewModel.todayExpense, color: MonAviBrand.alert)
                pill(icon: "arrow.up", amount: viewModel.todayIncome, color: MonAviBrand.primary)
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
            Text(amount, format: .appCurrency)
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
                    Text("Tu suscripción no se va a renovar")
                        .font(.subheadline.weight(.medium))
                    if let endDate = appState.subscriptionStore.currentPeriodEndDate {
                        Text("Finaliza el \(endDate.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: .monavi))) — hasta ahí tienes acceso completo.")
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
        .background(RoundedRectangle(cornerRadius: 14).fill(MonAviBrand.alert.opacity(0.12)))
    }

    /// Cuentas por pagar pendientes, mas cercanas primero — el diferenciador
    /// de MonAvi necesita ser visible aqui, no escondido en Ajustes.
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
                        Text("\(next.name) — \(next.dueDateValue.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))\(next.isOverdue ? " (vencida)" : "")")
                            .font(.caption)
                            .foregroundStyle(next.isOverdue ? MonAviBrand.alert : .secondary)
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

    /// "Tu ahorro": lo primero despues del dia. Total apartado en metas y
    /// el avance de las mas cercanas; invita a crear la primera meta.
    private var savingsCard: some View {
        NavigationLink {
            SavingsGoalsView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Una sola linea: "Tu ahorro ›   $1,840.00 · 3 metas", y debajo la
                // meta principal. Compacto para que los presupuestos se vean.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label("Tu ahorro", systemImage: "banknote.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MonAviBrand.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !savingsViewModel.goals.isEmpty {
                        Text(totalSaved, format: .appCurrency)
                            .font(.system(size: 19, weight: .heavy, design: MonAviBrand.fontDesign))
                            .foregroundStyle(.primary)
                    }
                    // Espacio para la X (va encima, fuera del enlace).
                    Color.clear.frame(width: 26, height: 1)
                }

                if savingsViewModel.goals.isEmpty {
                    Text("Crea tu primera meta y aparta algo cada semana.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                } else {
                    ForEach(savingsViewModel.goals.prefix(1)) { goal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(goal.emoji) \(goal.name)")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int((goal.progress * 100).rounded()))%")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: goal.progress)
                                .tint(MonAviBrand.primary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { hideSavingsCard = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ocultar Tu ahorro")
        }
    }

    /// Gasto anotado dos meses seguidos: "Pagaste Luz el 12 de octubre y
    /// el 13 de noviembre ($55). ¿Este mes ya lo pagaste?" — Sí con el
    /// mismo monto, Sí con otro monto, Aún no (queda como fijo y se
    /// recuerda) o No es fijo. Si ya lo anoto este mes, solo se pregunta si
    /// se guarda como fijo. Lo mismo llega como notificacion.
    @ViewBuilder
    private var recurringSuggestionCards: some View {
        if viewModel.isViewingToday && !isSearching {
            ForEach(suggestionsModel.suggestions.filter { !hiddenForNow.contains("s-\($0.id)") }) { suggestion in
                suggestionCard(suggestion)
            }
        }
    }

    private func suggestionCard(_ suggestion: RecurringDetector.Suggestion) -> some View {
        let amount = suggestion.amount.formatted(.appCurrency)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("🔁")
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.paidThisMonth ? L("¿%@ es un gasto fijo?", "\(suggestion.name)") : L("¿Ya pagaste %@ este mes?", "\(suggestion.name)"))
                        .font(.subheadline.weight(.semibold))
                    Text(suggestion.paidThisMonth
                         ? L("Lo pagaste %@ (%@). Si lo guardamos como fijo, te lo recordamos cada mes.", "\(suggestion.datesText)", "\(amount)")
                         : L("Lo pagaste %@ (%@). ¿Lo registramos este mes?", "\(suggestion.datesText)", "\(amount)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if suggestion.paidThisMonth {
                HStack(spacing: 8) {
                    Button("Sí, guardarlo como fijo") {
                        Task { await acceptSuggestion(suggestion, paidAmount: nil) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    Button("No es fijo") { dismissSuggestion(suggestion) }
                        .buttonStyle(.bordered)
                }
                .font(.footnote.weight(.semibold))
            } else {
                HStack(spacing: 8) {
                    Button("Sí, \(amount)") {
                        Task { await acceptSuggestion(suggestion, paidAmount: suggestion.amount) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    Button("Sí, otro monto") {
                        suggestionAmountText = ""
                        otherAmountSuggestion = suggestion
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote.weight(.semibold))
                HStack(spacing: 16) {
                    Button("Aún no lo pago") {
                        Task { await acceptSuggestion(suggestion, paidAmount: nil) }
                    }
                    Button("No es un gasto fijo") { dismissSuggestion(suggestion) }
                        .foregroundStyle(.secondary)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(MonAviBrand.primary.opacity(0.1)))
        .overlay(alignment: .topTrailing) { hideForNowButton("s-\(suggestion.id)") }
    }

    /// X para ocultar un aviso por ahora (no responde nada: vuelve a
    /// aparecer la proxima vez que se abra la app).
    private func hideForNowButton(_ key: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { _ = hiddenForNow.insert(key) }
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ocultar por ahora")
    }

    private func dismissSuggestion(_ suggestion: RecurringDetector.Suggestion) {
        guard let userId = appState.currentUserId else { return }
        suggestionsModel.dismiss(suggestion, userId: userId)
    }

    private func acceptSuggestion(_ suggestion: RecurringDetector.Suggestion, paidAmount: Decimal?) async {
        guard let userId = appState.currentUserId else { return }
        do {
            try await suggestionsModel.accept(suggestion, userId: userId, paidAmount: paidAmount, using: recurringViewModel)
            if paidAmount != nil { await refresh() }
        } catch {
            viewModel.errorMessage = L("No se pudo guardar el pago fijo: %@", "\(error.localizedDescription)")
        }
    }

    private var isSuggestionAmountShown: Binding<Bool> {
        Binding(get: { otherAmountSuggestion != nil }, set: { if !$0 { otherAmountSuggestion = nil } })
    }

    /// Aviso fuerte cuando el estudio real detecta sobreendeudamiento o que
    /// gasta mas de lo que gana. Toca para ver el analisis completo.
    private func debtAlertBanner(_ alert: FinancialSnapshot.Alert) -> some View {
        NavigationLink {
            FinancialHealthView()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(alert.title)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(alert.message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    /// "Tu Visa vence el 15 (en 3 días): debes $1,600 · mínimo $80" con el
    /// boton para registrar el pago y de que cuenta salio.
    @ViewBuilder
    private var cardDueRows: some View {
        if viewModel.isViewingToday && !isSearching {
            ForEach(CreditCardSchedule.upcoming(viewModel.debts)) { item in
                let days = CreditCardSchedule.daysUntil(item.due)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("💳")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(days == 0 ? L("Hoy vence %@", "\(item.debt.creditor)") : (days == 1 ? L("%@ vence en 1 día", "\(item.debt.creditor)") : L("%@ vence en %@ días", "\(item.debt.creditor)", "\(days)")))
                                .font(.subheadline.weight(.semibold))
                            Text("Debes \(item.debt.balance.formatted(.appCurrency)) · mínimo \(item.debt.estimatedMinimum.formatted(.appCurrency))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button("Registrar pago") {
                        cardPaymentRequest = CardPaymentRequest(debtId: item.debt.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .font(.footnote.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
            }
        }
    }

    /// "¿Ya está disponible tu dinero de Ahorros?": llego la fecha que marco
    /// para un ahorro bloqueado (plazo fijo, ahorro navideño) y todavia
    /// tiene dinero. Sin bloqueo no sale nada: siempre esta disponible.
    @ViewBuilder
    private var savingsAvailableRows: some View {
        if viewModel.isViewingToday && !isSearching {
            ForEach(viewModel.accounts.filter { SavingsAvailability.isDue($0) }) { account in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("💰")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("¿Ya está disponible tu dinero de \(account.name)?")
                                .font(.subheadline.weight(.semibold))
                            Text(L("Marcaste que se liberaba el %@. Tienes %@.", SavingsAvailability.label(account.availableOn) ?? L("día de hoy"), account.balance.formatted(.currency(code: account.currency))))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button("Sí, pasarlo a otra cuenta") {
                            transferRequest = AccountTransferRequest(sourceAccountId: account.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MonAviBrand.primary)
                        Button("Aún no") {
                            snoozeDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                            snoozeAccount = account
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(MonAviBrand.primary.opacity(0.1)))
            }
        }
    }

    private func saveSnooze() async {
        guard let account = snoozeAccount else { return }
        do {
            try await AccountTransfers.setAvailableOn(snoozeDate, accountId: account.id)
        } catch {
            viewModel.errorMessage = L("No se pudo cambiar la fecha: %@", "\(error.localizedDescription)")
        }
        snoozeAccount = nil
        await refresh()
    }

    // MARK: - El guardián de tu dinero

    private var moneyGuard: MoneyGuard {
        MoneyGuard(
            accounts: viewModel.accounts,
            transactions: guardTransactions,
            budgets: budgetsViewModel.progresses,
            pendingBills: billsViewModel.pending
        )
    }

    /// Alertas de peligro (cuenta en negativo, gastar más de lo que entra,
    /// categorías disparadas, pagos que no alcanzan). Máximo 3 a la vez;
    /// la X las oculta solo por ahora.
    @ViewBuilder
    private var moneyGuardRows: some View {
        if let incomeStatus, !hiddenForNow.contains("g-income") {
            if incomeStatus.inReview {
                incomeNotice(
                    emoji: "🛡️",
                    title: L("Tu cashback está en revisión"),
                    message: L("Revisamos algunos movimientos recientes. Lo nuevo queda pendiente hasta que terminemos; tu cuenta sigue igual."),
                    action: nil
                )
                .overlay(alignment: .topTrailing) { hideForNowButton("g-income") }
            } else if incomeStatus.shouldOfferVerification {
                incomeNotice(
                    emoji: "✅",
                    title: L("Verifica tus ingresos"),
                    message: L("Tus ingresos pasan de %@ al mes. Verifícalos para que cuenten completos para tu cashback.", incomeStatus.cap.formatted(.appCurrency)),
                    action: L("Verificar ahora")
                )
                .overlay(alignment: .topTrailing) { hideForNowButton("g-income") }
            }
        }
        let warnings = moneyGuard.warnings.filter { !hiddenForNow.contains("g-\($0.id)") }.prefix(3)
        ForEach(Array(warnings)) { warning in
            moneyGuardRow(warning)
                .overlay(alignment: .topTrailing) { hideForNowButton("g-\(warning.id)") }
        }
    }

    private func moneyGuardRow(_ warning: MoneyGuard.Warning) -> some View {
        let tint = guardTint(warning.severity)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(warning.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.title)
                        .font(.subheadline.weight(.semibold))
                    Text(warning.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
            }
            if let action = warning.action, let title = warning.actionTitle {
                Button(title) { perform(action) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(warning.severity == .danger ? 0.1 : 0.12)))
    }

    private func incomeNotice(emoji: String, title: String, message: String, action: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
            }
            if let action {
                Button(action) { isShowingIncomeVerification = true }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(MonAviBrand.primary.opacity(0.1)))
    }

    private func guardTint(_ severity: MoneyGuard.Warning.Severity) -> Color {
        switch severity {
        case .danger: return .red
        case .caution: return .orange
        case .info: return MonAviBrand.primary
        }
    }

    private func perform(_ action: MoneyGuard.Warning.Action) {
        switch action {
        case .recordIncome(let accountId):
            incomeRequest = IncomeRequest(accountId: accountId)
        case .openBudget(let budgetId):
            selectedBudgetProgress = budgetsViewModel.progresses.first { $0.budget.id == budgetId }
        case .openSpending:
            isShowingSpending = true
        case .openBills:
            isShowingBills = true
        }
    }

    /// Movimientos desde 3 meses antes del inicio de este mes (para
    /// comparar con el promedio) y el aviso de cuenta en negativo.
    private func refreshGuard() async {
        guard let userId = appState.currentUserId else { return }
        let calendar = Calendar.current
        if let monthStart = calendar.dateInterval(of: .month, for: Date())?.start,
           let since = calendar.date(byAdding: .month, value: -3, to: monthStart),
           let items = try? await TransactionsRepository.shared.fetchSince(userId: userId, date: since, limit: 3000) {
            guardTransactions = items
        }
        NotificationManager.scheduleNegativeBalanceReminder(moneyGuard.negativeAccounts)
        incomeStatus = try? await IncomeVerificationService.status()
    }

    private func refreshHealthAlert() async {
        guard let userId = appState.currentUserId,
              let result = try? await FinancialHealthLoader.load(userId: userId) else { return }
        healthAlert = result.snapshot.debtAlert
    }

    /// "Tus cuentas": el saldo de cada una (banco, efectivo, ahorros,
    /// tarjeta) a la vista en Hoy. Antes solo estaban en Ajustes > Cuentas
    /// y la cuenta de ahorros del onboarding "no se veia".
    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tus cuentas")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    DashboardView()
                } label: {
                    Text("Ver todas")
                        .font(.subheadline.weight(.semibold))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.accounts) { account in
                        NavigationLink {
                            DashboardView()
                        } label: {
                            AccountBalanceChip(
                                account: account,
                                available: viewModel.availableCredit(for: account),
                                lockedUntil: SavingsAvailability.isLocked(account) ? SavingsAvailability.label(account.availableOn) : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var amountPromptTitle: String {
        guard let item = amountPromptItem else { return "" }
        return item.movementType.isInflow ? L("¿Cuánto recibiste de %@?", "\(item.name)") : L("¿Cuánto pagaste de %@?", "\(item.name)")
    }

    private var isAmountPromptShown: Binding<Bool> {
        Binding(get: { amountPromptItem != nil }, set: { if !$0 { amountPromptItem = nil } })
    }

    private var totalSaved: Decimal {
        savingsViewModel.goals.reduce(Decimal(0)) { $0 + $1.currentAmount }
    }

    /// "¿Pagaste la luz hoy?" — recordatorio de una recurrente que le toca
    /// hoy y todavia no se ha confirmado. Los fijos pueden variar (la luz no
    /// es igual cada mes): se confirma el monto de siempre con un toque, o
    /// se escribe el que de verdad fue con "Fue otro monto".
    @ViewBuilder
    private func recurringReminderRow(_ item: RecurringTransaction) -> some View {
        let isIncome = item.movementType.isInflow
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(isIncome ? "💵" : "🧾")
                VStack(alignment: .leading, spacing: 2) {
                    Text(isIncome ? L("¿Recibiste %@ hoy?", "\(item.name)") : L("¿Pagaste %@ hoy?", "\(item.name)"))
                        .font(.subheadline.weight(.semibold))
                    Text("Normalmente son \(item.amount, format: .appCurrency). ¿Fue lo mismo?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button("Sí, \(item.amount.formatted(.appCurrency))") {
                    Task { await confirmRecurring(item) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Fue otro monto") {
                    customAmountText = ""
                    amountPromptItem = item
                }
                .buttonStyle(.bordered)

                Button("Aún no") {
                    recurringViewModel.dismissReminder(for: item)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .font(.footnote.weight(.semibold))
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
                    Text("Nada por ahí.")
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
                    Text(viewModel.isViewingToday ? L("Todavía no has anotado nada hoy. Toca el + para empezar.") : L("No hay movimientos ese día."))
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

    /// Deslizar a la izquierda = eliminar (con confirmacion); a la derecha =
    /// editar. Tocar tambien edita y mantener presionado muestra el menu.
    /// Un movimiento que viene de una factura se edita sin cambiar el monto
    /// (categoria y descripcion); al eliminarlo se quita su cashback.
    @ViewBuilder
    private func journalRow(_ transaction: FinanceTransaction) -> some View {
        SwipeActionsRow(
            onEdit: { editingTransaction = transaction },
            onDelete: { pendingDeletion = transaction }
        ) {
            journalRowContent(transaction)
                .contentShape(Rectangle())
                .onTapGesture { open(transaction) }
        }
        .contextMenu {
            Button {
                editingTransaction = transaction
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDeletion = transaction
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func open(_ transaction: FinanceTransaction) {
        editingTransaction = transaction
    }

    @ViewBuilder
    private func journalRowContent(_ transaction: FinanceTransaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(CategoryDisplay.emoji(for: transaction.category) ?? transaction.movementType.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description ?? CategoryDisplay.name(for: transaction.category) ?? transaction.movementType.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(transaction.occurredAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .monavi)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if transaction.description != nil, let categoryName = CategoryDisplay.name(for: transaction.category).map({ CategoryDisplay.label(for: $0) }) {
                        Text("· \(categoryName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if transaction.isFromInvoice {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Con factura")
                    }
                    if let points = pointsByTransaction[transaction.id] {
                        Text("+\(Cashback.format(cents: points)) de cashback")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MonAviBrand.primary.opacity(0.15)))
                            .foregroundStyle(MonAviBrand.primary)
                    }
                }
            }

            Spacer()

            Text(transaction.amount, format: .appCurrency)
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
                .accessibilityLabel("Anotar movimiento")
                .contextMenu {
                    Button {
                        isRecordingDebtPayment = true
                    } label: {
                        Label("Pago de deuda", systemImage: "creditcard.trianglebadge.exclamationmark")
                    }

                    Button {
                        isContributingToSavings = true
                    } label: {
                        Label("Aportar a meta", systemImage: "target")
                    }
                }

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
                .accessibilityLabel("Buscar")

                /// Acceso directo a escanear una factura DGI y ganar puntos —
                /// antes solo se llegaba ahi en 3 toques (Hoy > Puntos >
                /// Facturas que suman > escanear). Aqui mismo, un toque.
                Button {
                    invoiceExpense = nil
                    startInvoiceScan()
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
                .background(Circle().fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .pressable()
                .accessibilityLabel("Escanear factura")
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
                    .background(Circle().fill(MonAviBrand.headerGradient))
                    .shadow(color: MonAviBrand.primary.opacity(0.4), radius: 10, y: 4)
            }
            .pressable()
            .accessibilityLabel("Anotar movimiento por voz")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Elige un día",
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
            .navigationTitle("Ver otro día")
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
        pointsByTransaction = await CardPointsRepository.shared.pointsByTransaction(
            userId: userId, day: viewModel.selectedDate
        )
        // Widget "Tu día": gastado hoy y en el mes, y ultimos movimientos.
        await DayWidgetUpdater.refresh(userId: userId)
        await refreshGuard()
    }

    /// Abre la revision del movimiento detectado que se toco en la
    /// notificacion (o queda esperando hasta que Hoy aparezca).
    @MainActor
    private func openQuickAddFromWidget(_ requestedAt: Date?) {
        guard let requestedAt else { return }
        router.quickAddRequestedAt = nil
        // Un toque viejo (mas de 2 minutos) ya no abre nada.
        guard Date().timeIntervalSince(requestedAt) < 120 else { return }
        isQuickAdding = true
    }

    @MainActor
    private func openDetectedMovement(_ id: UUID?) {
        guard let id else { return }
        router.detectedMovementToReview = nil
        if let movement = detectedStore.movement(id: id) {
            reviewingDetected = movement
        }
    }

    /// "Registrar" en la tarjeta de Hoy: cuenta y categoria sugeridas.
    @MainActor
    private func quickRegisterDetected(_ movement: DetectedMovement) async {
        guard let userId = appState.currentUserId,
              let accountId = DetectedMovementActions.suggestedAccountId(for: movement, accounts: viewModel.accounts) else {
            reviewingDetected = movement
            return
        }
        do {
            try await DetectedMovementActions.register(
                movement,
                userId: userId,
                accountId: accountId,
                category: DetectedMovementActions.suggestedCategory(for: movement),
                description: nil,
                rememberCard: false
            )
            await refresh()
            await refreshBudgets()
        } catch {
            reviewingDetected = movement
        }
    }

    private func search() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.search(userId: userId)
    }

    private func refreshBudgets() async {
        guard let userId = appState.currentUserId else { return }
        await budgetsViewModel.refresh(userId: userId)
        didLoadBudgets = true
    }

    /// Hoy sin presupuestos: invitacion a crear el primero, en el mismo
    /// lugar donde luego van las barras.
    private var emptyBudgetsCard: some View {
        Button {
            isAddingBudget = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MonAviBrand.primary)
                    .frame(width: 40, height: 40)
                    .background(MonAviBrand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crea tu primer presupuesto")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Pon un límite por categoría (comida, súper…) y mira aquí cuánto te queda.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MonAviBrand.primary)
                // Espacio para la X (va encima, fuera del boton).
                Color.clear.frame(width: 22, height: 1)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { hideBudgetInvite = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ocultar Crea tu primer presupuesto")
        }
    }

    private func refreshRecurring() async {
        guard let userId = appState.currentUserId else { return }
        await recurringViewModel.refresh(userId: userId)
        await suggestionsModel.refresh(userId: userId, existing: recurringViewModel.items)
    }

    private func refreshBills() async {
        guard let userId = appState.currentUserId else { return }
        await billsViewModel.refresh(userId: userId)
    }

    /// "Premios para ti": si falla o no hay productos, se esconde.
    /// Solo el aviso discreto (punto en el boton de regalo) y las metas de
    /// ahorro: los premios no se muestran en Hoy.
    private func refreshFeaturedRewards() async {
        guard let userId = appState.currentUserId else { return }
        await savingsViewModel.refresh(userId: userId)
        activeGiftsCount = await RewardsRepository.shared.fetchActiveGiftsOrEmpty(userId: userId).count
    }

    private func refreshDgiConsent() async {
        guard let userId = appState.currentUserId else { return }
        await dgiViewModel.refresh(userId: userId)
    }

    /// «¿Te dieron factura?» > "Escanear factura": la camara se abre en
    /// cuanto la hoja de anotar termina de cerrarse, unida a ese gasto.
    private func openPendingInvoiceForExpense() {
        guard let expense = pendingInvoiceExpense else { return }
        pendingInvoiceExpense = nil
        invoiceExpense = expense
        Task {
            if dgiViewModel.hasConsented == nil { await refreshDgiConsent() }
            startInvoiceScan()
        }
    }

    private func startInvoiceScan() {
        if dgiViewModel.hasConsented == true {
            isShowingInvoiceScanner = true
        } else {
            isShowingDgiConsent = true
        }
    }

    private func delete(_ transaction: FinanceTransaction) async {
        do {
            try await viewModel.deleteTransaction(transaction)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func confirmRecurring(_ item: RecurringTransaction, amount: Decimal? = nil) async {
        guard let userId = appState.currentUserId else { return }
        do {
            try await recurringViewModel.confirmPayment(for: item, userId: userId, amount: amount)
        } catch {
            viewModel.errorMessage = L("No se pudo registrar el pago: %@", "\(error.localizedDescription)")
        }
        await refresh()
    }

    /// Paso la medianoche: Hoy pasa al dia nuevo y se muestra el resumen
    /// del dia que se cerro solo.
    private func handleDayChangeIfNeeded() async {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != lastActiveDay else { return }
        let wasViewingThatDay = Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: lastActiveDay)
        lastActiveDay = today
        if wasViewingThatDay {
            viewModel.selectedDate = Date()
            await refresh()
        }
        await showPreviousDayIfNeeded()
    }

    private func showPreviousDayIfNeeded() async {
        guard let userId = appState.currentUserId, daySummary == nil else { return }
        guard let summary = await viewModel.previousDaySummaryIfNeeded(userId: userId) else { return }
        // Un momento para que termine de abrir la pantalla.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !router.isVoiceCapturePresented else { return }
        daySummary = summary
    }

    private func closeDay() async {
        guard let userId = appState.currentUserId else { return }
        isClosingDay = true
        defer { isClosingDay = false }
        daySummary = await viewModel.closeDaySummary(userId: userId)
    }
}

extension DaySummary: Identifiable {
    var id: String { "\(income)-\(expense)-\(mood.title)-\(dayLabel ?? "hoy")" }
}

/// Tarjetita de una cuenta en "Tus cuentas" (Hoy). En una tarjeta de
/// credito: lo que debes y el cupo que te queda.
private struct AccountBalanceChip: View {
    let account: Account
    var available: Decimal? = nil
    /// "1 de diciembre" si el dinero sigue bloqueado.
    var lockedUntil: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: AccountIcon.symbol(for: account.type))
                    .foregroundStyle(MonAviBrand.primary)
                Text(account.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            Text(account.displayAmount, format: .currency(code: account.currency))
                .font(.headline)
                .foregroundStyle(account.type.isLiability ? Color.orange : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let lockedUntil {
                Label("Libre el \(lockedUntil)", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let available {
                Text("\(account.balanceCaption) · disponible \(available.formatted(.currency(code: account.currency)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(account.balanceCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

/// «Anotar el ingreso» desde el guardián: en qué cuenta.
private struct IncomeRequest: Identifiable {
    let id = UUID()
    let accountId: UUID?
}
