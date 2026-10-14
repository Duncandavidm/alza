import Foundation

enum SpendingPeriod: String, CaseIterable, Identifiable {
    case thisMonth
    case last3Months

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisMonth: return "Este mes"
        case .last3Months: return "Ultimos 3 meses"
        }
    }
}

struct CategorySpend: Identifiable {
    let id = UUID()
    let category: String
    let total: Decimal
    let previousTotal: Decimal

    /// nil si no hay con que comparar (categoria nueva este periodo).
    var deltaPercent: Decimal? {
        guard previousTotal > 0 else { return nil }
        return ((total - previousTotal) / previousTotal) * 100
    }
}

/// "¿En que estoy gastando mas?" — agrupa los gastos (movement_type =
/// gasto) por categoria para el periodo elegido, y los compara contra el
/// periodo equivalente anterior para detectar categorias que van
/// creciendo (inspirado en el "Spending Insights" del prompt original).
@MainActor
final class SpendingInsightsViewModel: ObservableObject {
    @Published var period: SpendingPeriod = .thisMonth {
        didSet { recompute() }
    }
    @Published private(set) var categorySpends: [CategorySpend] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var allTransactions: [FinanceTransaction] = []

    var totalSpend: Decimal {
        categorySpends.reduce(0) { $0 + $1.total }
    }

    var topCategories: [CategorySpend] {
        Array(categorySpends.sorted { $0.total > $1.total }.prefix(3))
    }

    func percent(of item: CategorySpend) -> Decimal? {
        guard totalSpend > 0 else { return nil }
        return (item.total / totalSpend) * 100
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            allTransactions = try await TransactionsRepository.shared.fetchAll(userId: userId)
            recompute()
        } catch {
            errorMessage = "No se pudo cargar tus gastos: \(error.localizedDescription)"
        }
    }

    private func recompute() {
        let calendar = Calendar.current
        let now = Date()
        let (currentRange, previousRange) = ranges(for: period, now: now, calendar: calendar)

        let currentExpenses = allTransactions.filter { $0.movementType == .gasto && currentRange.contains($0.occurredAt) }
        let previousExpenses = allTransactions.filter { $0.movementType == .gasto && previousRange.contains($0.occurredAt) }

        let currentByCategory = Dictionary(grouping: currentExpenses) { $0.category ?? "Otro" }
            .mapValues { items in items.reduce(Decimal(0)) { $0 + abs($1.amount) } }
        let previousByCategory = Dictionary(grouping: previousExpenses) { $0.category ?? "Otro" }
            .mapValues { items in items.reduce(Decimal(0)) { $0 + abs($1.amount) } }

        let allCategories = Set(currentByCategory.keys).union(previousByCategory.keys)
        categorySpends = allCategories.compactMap { category -> CategorySpend? in
            let total = currentByCategory[category] ?? 0
            guard total > 0 else { return nil }
            return CategorySpend(category: category, total: total, previousTotal: previousByCategory[category] ?? 0)
        }.sorted { $0.total > $1.total }
    }

    private func ranges(for period: SpendingPeriod, now: Date, calendar: Calendar) -> (current: DateInterval, previous: DateInterval) {
        let startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now

        switch period {
        case .thisMonth:
            let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            return (
                DateInterval(start: startOfThisMonth, end: now),
                DateInterval(start: startOfLastMonth, end: startOfThisMonth)
            )
        case .last3Months:
            let start3MonthsAgo = calendar.date(byAdding: .month, value: -3, to: startOfThisMonth) ?? startOfThisMonth
            let start6MonthsAgo = calendar.date(byAdding: .month, value: -6, to: startOfThisMonth) ?? startOfThisMonth
            return (
                DateInterval(start: start3MonthsAgo, end: now),
                DateInterval(start: start6MonthsAgo, end: start3MonthsAgo)
            )
        }
    }
}
