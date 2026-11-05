import SwiftUI
import Charts

enum SummaryChartMode: Hashable {
    case donut
    case bars
}

/// "Resumen": todos tus gastos (o ingresos) del periodo de un vistazo —
/// torta por categoria o barras por dia/semana/mes con linea de promedio,
/// filtros de tipo, periodo y cuenta, y la lista de movimientos abajo.
struct SummaryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SummaryViewModel()
    /// Reusa la logica de "Anotar movimiento" del cuaderno del dia (cuenta
    /// por default, guardar, editar) para el boton "+" y para editar.
    @StateObject private var journalViewModel = DayJournalViewModel()

    @State private var mode: SummaryChartMode = .donut
    /// Seleccion "en vivo" mientras el dedo esta sobre la grafica de barras.
    @State private var touchedBucketLabel: String?
    /// Ultima barra tocada: se queda fija hasta quitarla con la "x".
    @State private var pinnedBucketLabel: String?
    @State private var selectedAngle: Double?
    @State private var selectedCategoryKey: String?
    @State private var isAdding = false
    @State private var editingTransaction: FinanceTransaction?

    private let calculator = SummaryCalculator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    filterBar
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Resumen")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) { addButton }
            .task { await reload() }
            .refreshable { await reload() }
            .onChange(of: viewModel.snapshot) { _, _ in clearSelection() }
            .onChange(of: mode) { _, _ in clearSelection() }
            .onChange(of: touchedBucketLabel) { _, newValue in
                if let newValue { pinnedBucketLabel = newValue }
            }
            .onChange(of: selectedAngle) { _, newValue in
                guard let newValue else { return }
                selectedCategoryKey = categoryKey(atAngleValue: newValue)
            }
            .sheet(isPresented: $isAdding, onDismiss: { Task { await reload() } }) {
                QuickAddView(viewModel: journalViewModel)
            }
            .sheet(item: $editingTransaction, onDismiss: { Task { await reload() } }) { transaction in
                QuickAddView(viewModel: journalViewModel, existingTransaction: transaction)
            }
            .alert("Algo salió mal", isPresented: errorBinding) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Hero (grafica)

    private var heroCard: some View {
        VStack(spacing: 14) {
            periodNavigator
            if mode == .bars {
                headline
                barChart
            } else {
                donutChart
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .foregroundStyle(MonAviBrand.onDarkSurface)
        .background(MonAviBrand.headerGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var periodNavigator: some View {
        HStack {
            navigatorButton(systemImage: "chevron.left", label: "Periodo anterior") {
                viewModel.goBack()
            }
            Spacer()
            Text(viewModel.snapshot?.title ?? " ")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            navigatorButton(systemImage: "chevron.right", label: "Periodo siguiente") {
                viewModel.goForward()
            }
            .opacity(viewModel.canGoForward ? 1 : 0.3)
            .disabled(!viewModel.canGoForward)
        }
    }

    private func navigatorButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private struct HeadlineContent {
        let label: String
        let amount: Decimal
        let delta: Decimal?
        let deltaLabel: String
    }

    private var headlineContent: HeadlineContent {
        guard let snapshot = viewModel.snapshot else {
            return HeadlineContent(label: " ", amount: 0, delta: nil, deltaLabel: "")
        }
        if mode == .bars,
           let label = activeBucketLabel,
           let bucket = snapshot.buckets.first(where: { $0.label == label }) {
            return HeadlineContent(
                label: calculator.selectionTitle(for: bucket.interval, period: snapshot.period),
                amount: bucket.total,
                delta: nil,
                deltaLabel: ""
            )
        }
        if mode == .donut,
           let key = selectedCategoryKey,
           let item = snapshot.categories.first(where: { $0.key == key }) {
            return HeadlineContent(
                label: "\(item.emoji) \(item.key)",
                amount: item.total,
                delta: item.deltaPercent,
                deltaLabel: snapshot.comparisonLabel
            )
        }
        return HeadlineContent(
            label: snapshot.kind == .expenses ? "Gastaste" : "Recibiste",
            amount: snapshot.total,
            delta: snapshot.deltaPercent,
            deltaLabel: snapshot.comparisonLabel
        )
    }

    private var headline: some View {
        let content = headlineContent
        return VStack(spacing: 4) {
            Text(content.label)
                .font(.caption.weight(.medium))
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(money(content.amount))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if let delta = content.delta {
                DeltaBadge(delta: delta, label: content.deltaLabel, increaseIsGood: viewModel.kind.increaseIsGood)
            }
        }
        .multilineTextAlignment(.center)
        .animation(.snappy, value: content.amount)
    }

    // MARK: - Barras

    private var activeBucketLabel: String? {
        touchedBucketLabel ?? pinnedBucketLabel
    }

    private var barChart: some View {
        let buckets = viewModel.snapshot?.buckets ?? []
        let average = (viewModel.snapshot?.averagePerBucket ?? 0).doubleValue
        let cornerRadius: CGFloat = buckets.count > 12 ? 3 : 8

        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Periodo", bucket.label),
                    y: .value("Total", bucket.total.doubleValue)
                )
                .foregroundStyle(barColor(for: bucket))
                .cornerRadius(cornerRadius)
            }

            if average > 0 {
                RuleMark(y: .value("Promedio", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Prom. \(compact(average))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MonAviBrand.onDarkSurface)
                    }
            }
        }
        .chartXSelection(value: $touchedBucketLabel)
        .chartXAxis {
            AxisMarks(values: axisLabels(for: buckets)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.75))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.12))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(compact(amount))
                            .font(.caption2)
                            .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.75))
                    }
                }
            }
        }
        .frame(height: 200)
        .animation(.snappy, value: buckets)
        .accessibilityLabel("Gráfica de barras del periodo")
    }

    private func barColor(for bucket: SummaryBucket) -> Color {
        guard let active = activeBucketLabel else { return MonAviBrand.accentOnDark }
        return bucket.label == active ? Color.white : MonAviBrand.accentOnDark.opacity(0.35)
    }

    /// Con muchas barras (dias del mes) se muestra una etiqueta cada tanto,
    /// para que no se encimen.
    private func axisLabels(for buckets: [SummaryBucket]) -> [String] {
        guard buckets.count > 7 else { return buckets.map(\.label) }
        let step = buckets.count > 20 ? 7 : (buckets.count > 10 ? 3 : 2)
        return buckets.enumerated()
            .filter { $0.offset % step == 0 }
            .map(\.element.label)
    }

    // MARK: - Torta

    private var donutChart: some View {
        let categories = viewModel.snapshot?.categories ?? []

        return ZStack {
            if categories.isEmpty {
                Circle()
                    .stroke(MonAviBrand.onDarkSurface.opacity(0.15), lineWidth: 22)
                    .padding(11)
            } else {
                Chart(categories) { item in
                    SectorMark(
                        angle: .value("Total", item.total.doubleValue),
                        innerRadius: .ratio(0.76),
                        angularInset: 2.5
                    )
                    .cornerRadius(6)
                    .foregroundStyle(color(for: item))
                    .opacity(selectedCategoryKey == nil || selectedCategoryKey == item.key ? 1 : 0.22)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngle)
            }

            headline
                .padding(.horizontal, 64)
                .onTapGesture {
                    withAnimation(.snappy) { selectedCategoryKey = nil }
                }
        }
        .frame(height: 270)
        .animation(.snappy, value: selectedCategoryKey)
        .accessibilityElement(children: .combine)
    }

    private func categoryKey(atAngleValue value: Double) -> String? {
        let categories = viewModel.snapshot?.categories ?? []
        var cumulative = 0.0
        for item in categories {
            cumulative += item.total.doubleValue
            if value <= cumulative { return item.key }
        }
        return categories.last?.key
    }

    private func color(for item: SummaryCategoryTotal) -> Color {
        item.category?.color ?? Color.gray
    }

    // MARK: - Filtros

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker("Vista", selection: $mode) {
                    Image(systemName: "chart.pie.fill")
                        .accessibilityLabel("Torta")
                        .tag(SummaryChartMode.donut)
                    Image(systemName: "chart.bar.fill")
                        .accessibilityLabel("Barras")
                        .tag(SummaryChartMode.bars)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)

                Menu {
                    Picker("Tipo", selection: $viewModel.kind) {
                        ForEach(SummaryKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                } label: {
                    FilterChip(title: viewModel.kind.displayName)
                }

                Menu {
                    Picker("Periodo", selection: $viewModel.period) {
                        ForEach(SummaryPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                } label: {
                    FilterChip(title: viewModel.period.displayName)
                }

                Menu {
                    Picker("Cuenta", selection: $viewModel.accountId) {
                        Text("Todas las cuentas").tag(UUID?.none)
                        ForEach(journalViewModel.accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } label: {
                    FilterChip(title: accountTitle)
                }

                if mode == .bars, let label = pinnedBucketLabel {
                    Button {
                        withAnimation(.snappy) { pinnedBucketLabel = nil }
                    } label: {
                        FilterChip(title: label, isActive: true, showsClear: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar filtro \(label)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var accountTitle: String {
        guard let accountId = viewModel.accountId,
              let account = journalViewModel.accounts.first(where: { $0.id == accountId })
        else { return "Todas las cuentas" }
        return account.name
    }

    // MARK: - Listas

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            if mode == .donut {
                categoryList(snapshot)
            } else {
                transactionList(snapshot)
            }
        } else if viewModel.isLoading {
            ProgressView().padding(.top, 40)
        }
    }

    private func categoryList(_ snapshot: SummarySnapshot) -> some View {
        VStack(spacing: 0) {
            if snapshot.categories.isEmpty {
                emptyState(snapshot)
            } else {
                ForEach(snapshot.categories) { item in
                    Button {
                        withAnimation(.snappy) {
                            selectedCategoryKey = selectedCategoryKey == item.key ? nil : item.key
                        }
                    } label: {
                        categoryRow(item, snapshot: snapshot)
                    }
                    .buttonStyle(.plain)

                    if item.id != snapshot.categories.last?.id {
                        Divider().padding(.leading, 66)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .background(cardBackground)
    }

    private func categoryRow(_ item: SummaryCategoryTotal, snapshot: SummarySnapshot) -> some View {
        let tint = color(for: item)
        let isSelected = selectedCategoryKey == item.key

        return HStack(spacing: 12) {
            CategoryIcon(emoji: item.emoji, color: tint)
            Text(item.key)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text("\(item.count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(money(item.total))
                    .font(.body.weight(.semibold))
                Text("\(snapshot.share(of: item).doubleValue, format: .number.precision(.fractionLength(1)))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.18)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? tint.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let transactions: [FinanceTransaction]
        let total: Decimal
        var id: Date { day }
    }

    private func dayGroups(for snapshot: SummarySnapshot) -> [DayGroup] {
        var items = snapshot.transactions
        if let label = pinnedBucketLabel,
           let bucket = snapshot.buckets.first(where: { $0.label == label }) {
            items = items.filter { $0.occurredAt >= bucket.interval.start && $0.occurredAt < bucket.interval.end }
        }
        let grouped = Dictionary(grouping: items.prefix(300)) { Calendar.current.startOfDay(for: $0.occurredAt) }
        return grouped
            .map { day, transactions in
                DayGroup(
                    day: day,
                    transactions: transactions.sorted { $0.occurredAt > $1.occurredAt },
                    total: transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
                )
            }
            .sorted { $0.day > $1.day }
    }

    private func transactionList(_ snapshot: SummarySnapshot) -> some View {
        let groups = dayGroups(for: snapshot)

        return VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                emptyState(snapshot)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(calculator.dayTitle(for: group.day))
                        Spacer()
                        Text(money(group.total))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(group.transactions) { transaction in
                            Button {
                                editingTransaction = transaction
                            } label: {
                                transactionRow(transaction, kind: snapshot.kind)
                            }
                            .buttonStyle(.plain)

                            if transaction.id != group.transactions.last?.id {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(cardBackground)
                }
            }
        }
    }

    private func transactionRow(_ transaction: FinanceTransaction, kind: SummaryKind) -> some View {
        let category = TransactionCategory(rawValue: transaction.category ?? "")
        let description = transaction.description?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = description.isEmpty
            ? (transaction.category ?? transaction.movementType.displayName)
            : description
        let subtitle: String? = description.isEmpty ? nil : transaction.category
        let sign = kind == .income ? "+" : "−"

        return HStack(spacing: 12) {
            CategoryIcon(
                emoji: category?.emoji ?? transaction.movementType.emoji,
                color: category?.color ?? Color.gray
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(sign + money(abs(transaction.amount)))
                .font(.body.weight(.semibold))
                .foregroundStyle(kind == .income ? MonAviBrand.primary : Color.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para editar")
    }

    private func emptyState(_ snapshot: SummarySnapshot) -> some View {
        ContentUnavailableView(
            snapshot.kind == .expenses ? "Sin gastos en este periodo" : "Sin ingresos en este periodo",
            systemImage: "chart.pie",
            description: Text("Toca + para anotar un movimiento.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Boton +

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(MonAviBrand.primary))
                .shadow(color: MonAviBrand.primary.opacity(0.35), radius: 10, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("Anotar movimiento")
    }

    // MARK: - Utilidades

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func clearSelection() {
        touchedBucketLabel = nil
        pinnedBucketLabel = nil
        selectedAngle = nil
        selectedCategoryKey = nil
    }

    private func reload() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        await journalViewModel.refresh(userId: userId)
    }

    private func money(_ value: Decimal) -> String {
        let decimals = abs(value) >= 1000 ? 0 : 2
        return value.formatted(.currency(code: "USD").precision(.fractionLength(decimals)))
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

/// Chip de filtro (Gastos, Mensual, Todas las cuentas...).
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    var isActive = false
    var showsClear = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
            Image(systemName: showsClear ? "xmark.circle.fill" : "chevron.down")
                .font(.caption2.weight(.bold))
                .opacity(showsClear ? 1 : 0.6)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(isActive ? MonAviBrand.primary.opacity(0.15) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            Capsule().strokeBorder(isActive ? MonAviBrand.primary : Color.clear, lineWidth: 1.5)
        )
        .foregroundStyle(isActive ? MonAviBrand.primary : Color.primary)
    }
}

/// "↑ 12% frente a octubre" — verde de marca si la variacion es a favor,
/// coral si es en contra (subir en gastos es en contra, en ingresos a favor).
struct DeltaBadge: View {
    let delta: Decimal
    let label: String
    let increaseIsGood: Bool

    var body: some View {
        let isUp = delta >= 0
        let isGood = isUp == increaseIsGood

        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(isGood ? MonAviBrand.accentOnDark : MonAviBrand.alertOnDark)
            Text("\(abs(delta).doubleValue, format: .number.precision(.fractionLength(0)))% \(label)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
    }
}
