import Foundation

/// Niveles e insignias: puntos por habitos financieros que la app puede
/// medir con los datos del propio usuario. Los puntos que cuentan (saldo
/// canjeable y nivel) los calcula el SERVIDOR (`award_habit_points`,
/// migracion 0036) con estas mismas reglas; este calculo local solo da el
/// desglose estimado por fuente, las insignias y el respaldo si no se
/// pudo leer el saldo. Las facturas DGI dan cashback, no puntos.
///
/// Las reglas estan pensadas para que hacer trampa no rinda:
/// - Constancia, no montos: se premia anotar cada dia y apartar algo cada
///   semana; anotar $10.000 falsos da lo mismo que $5.
/// - Los dias "anotados" se cuentan por `created_at` (hora del servidor),
///   no por la fecha que el usuario le pone al movimiento: no se puede
///   rellenar una racha hacia atras.
/// - Un aporte de ahorro solo cuenta si cuadra con lo que el usuario
///   registro ese mes (ingresos - gastos) y si pasan 30 dias sin retiros
///   de esa meta ("madura").
/// - Un presupuesto solo cuenta como cumplido si ese periodo el usuario
///   realmente estuvo anotando (un mes vacio no es un mes sin gastos).
/// - Tope de puntos por mes (400, igual que el servidor).
struct HabitEngine {
    enum Rules {
        static let xpPerLoggedDay = 5
        static let xpPerSavingsWeek = 25
        static let xpPerMonthlyBudgetMet = 30
        static let xpPerWeeklyBudgetMet = 10
        static let monthlyXPCap = 400
        static let maturationDays = 30
        static let minLoggedDaysForMonthlyBudget = 10
        static let minLoggedDaysForWeeklyBudget = 3
    }

    var calendar: Calendar = .current
    var now: Date = Date()

    // MARK: - Entrada / salida

    struct Input {
        var transactions: [FinanceTransaction]
        var budgets: [Budget]
        var goals: [SavingsGoal]
        var contributions: [SavingsContribution]
        /// Fechas de facturas DGI confirmadas. Solo para las insignias de
        /// facturas: NO dan puntos (las facturas dan cashback).
        var verifiedReceiptDates: [Date] = []
    }

    enum XPSource: String, CaseIterable, Identifiable {
        case logging, savings, budgets

        var id: String { rawValue }

        var title: String {
            switch self {
            case .logging: return "Anotar tus movimientos"
            case .savings: return "Ahorro constante"
            case .budgets: return "Presupuestos cumplidos"
            }
        }

        var emoji: String {
            switch self {
            case .logging: return "📝"
            case .savings: return "🐷"
            case .budgets: return "✅"
            }
        }

        var rule: String {
            switch self {
            case .logging: return "+\(Rules.xpPerLoggedDay) puntos por cada día que anotas algo"
            case .savings: return "+\(Rules.xpPerSavingsWeek) puntos por cada semana con un aporte que madura (30 días sin retirar)"
            case .budgets: return "+\(Rules.xpPerMonthlyBudgetMet) puntos por mes (+\(Rules.xpPerWeeklyBudgetMet) por semana) sin pasarte de un presupuesto"
            }
        }
    }

    enum ContributionStatus: Equatable {
        /// Ya pasaron 30 dias sin retiros: cuenta para tu nivel.
        case matured
        /// Esperando sus 30 dias.
        case maturing(on: Date)
        /// Hubo un retiro de esa meta antes de los 30 dias.
        case broken
        /// No cuadra con lo que registraste ese mes (ingresos - gastos).
        case unbacked
    }

    struct ContributionReview: Identifiable, Equatable {
        let contribution: SavingsContribution
        let status: ContributionStatus
        var id: UUID { contribution.id }
    }

    struct Progress: Equatable {
        let totalXP: Int
        let xpThisMonth: Int
        let xpBySource: [XPSource: Int]
        let level: HabitLevel
        let currentStreak: Int
        let bestStreak: Int
        let badges: [HabitBadge]
        /// Aportes positivos, del mas reciente al mas antiguo.
        let contributionReviews: [ContributionReview]
        /// true si `totalXP`/`xpThisMonth` vienen del servidor
        /// (`points_balances.habit_points_earned`); false si son el
        /// calculo local de respaldo.
        var isFromServer: Bool = false

        var earnedBadges: [HabitBadge] { badges.filter(\.isEarned) }

        /// Mismo progreso con el total (y lo del mes) que calculo el
        /// servidor: el nivel sale de ahi. El desglose por fuente, la
        /// racha y las insignias siguen siendo los locales (estimado).
        func withServerTotals(totalXP serverTotal: Int, xpThisMonth serverMonth: Int?) -> Progress {
            let total = max(0, serverTotal)
            return Progress(
                totalXP: total,
                xpThisMonth: min(HabitEngine.Rules.monthlyXPCap, max(0, serverMonth ?? xpThisMonth)),
                xpBySource: xpBySource,
                level: HabitLevel.level(forXP: total),
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                badges: badges,
                contributionReviews: contributionReviews,
                isFromServer: true
            )
        }
    }

    private struct XPEvent {
        let date: Date
        let xp: Int
        let source: XPSource
    }

    // MARK: - Calculo

    func progress(for input: Input) -> Progress {
        let loggedDays = Set(input.transactions.map { calendar.startOfDay(for: $0.createdAt) })
        let reviews = reviewContributions(input)
        let budgetPeriodsMet = metBudgetPeriods(input, loggedDays: loggedDays)

        var events: [XPEvent] = loggedDays.map {
            XPEvent(date: $0, xp: Rules.xpPerLoggedDay, source: .logging)
        }

        let savingsWeeks = maturedSavingsWeeks(reviews)
        events += savingsWeeks.map {
            XPEvent(date: $0.maturedOn, xp: Rules.xpPerSavingsWeek, source: .savings)
        }
        events += budgetPeriodsMet.map {
            XPEvent(
                date: $0.end,
                xp: $0.period == .monthly ? Rules.xpPerMonthlyBudgetMet : Rules.xpPerWeeklyBudgetMet,
                source: .budgets
            )
        }

        let (total, bySource, thisMonth) = applyMonthlyCap(events)
        let (current, best) = streaks(loggedDays)

        let badges = makeBadges(
            input: input,
            loggedDays: loggedDays,
            bestStreak: best,
            savingsWeekStarts: savingsWeeks.map(\.weekStart),
            reviews: reviews,
            budgetPeriodsMet: budgetPeriodsMet
        )

        return Progress(
            totalXP: total,
            xpThisMonth: thisMonth,
            xpBySource: bySource,
            level: HabitLevel.level(forXP: total),
            currentStreak: current,
            bestStreak: best,
            badges: badges,
            contributionReviews: reviews
                .filter { $0.contribution.amount > 0 }
                .sorted { $0.contribution.createdAt > $1.contribution.createdAt }
        )
    }

    /// Suma la XP mes por mes sin pasar del tope mensual (los eventos mas
    /// antiguos del mes entran primero).
    private func applyMonthlyCap(_ events: [XPEvent]) -> (total: Int, bySource: [XPSource: Int], thisMonth: Int) {
        let byMonth = Dictionary(grouping: events) { startOf(.month, for: $0.date) }
        let currentMonth = startOf(.month, for: now)
        var total = 0
        var thisMonth = 0
        var bySource: [XPSource: Int] = [:]

        for (month, monthEvents) in byMonth {
            var monthTotal = 0
            for event in monthEvents.sorted(by: { $0.date < $1.date }) {
                let granted = min(event.xp, Rules.monthlyXPCap - monthTotal)
                guard granted > 0 else { break }
                monthTotal += granted
                bySource[event.source, default: 0] += granted
            }
            total += monthTotal
            if month == currentMonth { thisMonth = monthTotal }
        }
        return (total, bySource, thisMonth)
    }

    // MARK: Racha

    /// Racha actual: dias seguidos con algo anotado, terminando hoy (o
    /// ayer, si hoy todavia no anota nada). Y la mejor racha historica.
    func streaks(_ loggedDays: Set<Date>) -> (current: Int, best: Int) {
        let today = calendar.startOfDay(for: now)
        var current = 0
        var cursor = loggedDays.contains(today) ? today : addDays(-1, to: today)
        while loggedDays.contains(cursor) {
            current += 1
            cursor = addDays(-1, to: cursor)
        }

        var best = 0
        var run = 0
        var previous: Date?
        for day in loggedDays.sorted() {
            if let previous, addDays(1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return (current, max(best, current))
    }

    // MARK: Ahorro

    func reviewContributions(_ input: Input) -> [ContributionReview] {
        let sorted = input.contributions.sorted { $0.createdAt < $1.createdAt }
        let backed = backedContributionIDs(sorted, transactions: input.transactions)

        return sorted.map { (contribution) -> ContributionReview in
            guard contribution.amount > 0 else {
                return ContributionReview(contribution: contribution, status: .broken)
            }
            guard backed.contains(contribution.id) else {
                return ContributionReview(contribution: contribution, status: .unbacked)
            }

            let maturesOn = addDays(Rules.maturationDays, to: contribution.createdAt)
            let withdrewBeforeMaturing = sorted.contains { other in
                other.goalId == contribution.goalId
                    && other.amount < 0
                    && other.createdAt > contribution.createdAt
                    && other.createdAt <= maturesOn
            }
            if withdrewBeforeMaturing {
                return ContributionReview(contribution: contribution, status: .broken)
            }
            return ContributionReview(
                contribution: contribution,
                status: maturesOn <= now ? .matured : .maturing(on: maturesOn)
            )
        }
    }

    /// Un aporte esta "respaldado" si, sumado a los aportes anteriores del
    /// mismo mes, no pasa de lo que el usuario registro como sobrante ese
    /// mes (ingresos - gastos). Sin ingresos anotados, no hay respaldo.
    private func backedContributionIDs(
        _ contributions: [SavingsContribution],
        transactions: [FinanceTransaction]
    ) -> Set<UUID> {
        var surplusByMonth: [Date: Decimal] = [:]
        for transaction in transactions {
            let month = startOf(.month, for: transaction.occurredAt)
            switch transaction.movementType {
            case .ingreso:
                surplusByMonth[month, default: 0] += abs(transaction.amount)
            case .gasto, .pagoProveedor:
                surplusByMonth[month, default: 0] -= abs(transaction.amount)
            case .inversion, .transferencia:
                break
            }
        }

        var usedByMonth: [Date: Decimal] = [:]
        var backed: Set<UUID> = []
        for contribution in contributions where contribution.amount > 0 {
            let month = startOf(.month, for: contribution.createdAt)
            let allowance = max(0, surplusByMonth[month] ?? 0)
            let used = usedByMonth[month] ?? 0
            if used + contribution.amount <= allowance {
                usedByMonth[month] = used + contribution.amount
                backed.insert(contribution.id)
            }
        }
        return backed
    }

    private struct SavingsWeek {
        let weekStart: Date
        let maturedOn: Date
    }

    /// Semanas (por la fecha del aporte) con al menos un aporte maduro.
    private func maturedSavingsWeeks(_ reviews: [ContributionReview]) -> [SavingsWeek] {
        var byWeek: [Date: Date] = [:]
        for review in reviews where review.status == .matured {
            let week = startOf(.weekOfYear, for: review.contribution.createdAt)
            let maturedOn = addDays(Rules.maturationDays, to: review.contribution.createdAt)
            byWeek[week] = min(byWeek[week] ?? maturedOn, maturedOn)
        }
        return byWeek.map { SavingsWeek(weekStart: $0.key, maturedOn: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: Presupuestos

    struct BudgetPeriodMet: Equatable {
        let budgetId: UUID
        let period: BudgetPeriod
        let start: Date
        let end: Date
    }

    /// Periodos ya cerrados (desde que existe el presupuesto) en los que el
    /// gasto de la categoria no paso del limite y el usuario estuvo
    /// anotando lo suficiente como para que el dato signifique algo.
    func metBudgetPeriods(_ input: Input, loggedDays: Set<Date>) -> [BudgetPeriodMet] {
        var result: [BudgetPeriodMet] = []
        for budget in input.budgets {
            let unit: Calendar.Component = budget.period == .monthly ? .month : .weekOfYear
            let minDays = budget.period == .monthly
                ? Rules.minLoggedDaysForMonthlyBudget
                : Rules.minLoggedDaysForWeeklyBudget

            // Primer periodo completo despues de crear el presupuesto.
            var start = startOf(unit, for: budget.createdAt)
            if start < budget.createdAt { start = add(unit, 1, to: start) }

            var guardCount = 0
            while guardCount < 200 {
                guardCount += 1
                let end = add(unit, 1, to: start)
                guard end <= now else { break }

                let daysLogged = loggedDays.filter { $0 >= start && $0 < end }.count
                let spent = input.transactions
                    .filter {
                        ($0.movementType == .gasto || $0.movementType == .pagoProveedor)
                            && $0.category == budget.category
                            && $0.occurredAt >= start && $0.occurredAt < end
                    }
                    .reduce(Decimal(0)) { $0 + abs($1.amount) }

                if daysLogged >= minDays && spent <= budget.limitAmount {
                    result.append(BudgetPeriodMet(budgetId: budget.id, period: budget.period, start: start, end: end))
                }
                start = end
            }
        }
        return result
    }

    // MARK: Insignias

    private func makeBadges(
        input: Input,
        loggedDays: Set<Date>,
        bestStreak: Int,
        savingsWeekStarts: [Date],
        reviews: [ContributionReview],
        budgetPeriodsMet: [BudgetPeriodMet]
    ) -> [HabitBadge] {
        let maxDaysInAMonth = Dictionary(grouping: loggedDays) { startOf(.month, for: $0) }
            .values.map(\.count).max() ?? 0
        let bestSavingsRun = longestConsecutiveWeeks(savingsWeekStarts)
        let monthlyBudgetsMet = budgetPeriodsMet.filter { $0.period == .monthly }.count

        var maturedByGoal: [UUID: Decimal] = [:]
        for review in reviews where review.status == .matured {
            maturedByGoal[review.contribution.goalId, default: 0] += review.contribution.amount
        }
        let completedGoal = input.goals.contains { goal in
            (maturedByGoal[goal.id] ?? 0) >= goal.targetAmount
        }

        return [
            HabitBadge(id: "first_step", emoji: "👣", title: "Primer paso",
                       detail: "Anota tu primer movimiento.",
                       current: loggedDays.isEmpty ? 0 : 1, target: 1),
            HabitBadge(id: "streak_7", emoji: "🔥", title: "Una semana seguida",
                       detail: "Anota algo 7 días seguidos.",
                       current: bestStreak, target: 7),
            HabitBadge(id: "streak_30", emoji: "⚡", title: "Mes imparable",
                       detail: "Anota algo 30 días seguidos.",
                       current: bestStreak, target: 30),
            HabitBadge(id: "full_month", emoji: "📅", title: "Mes completo",
                       detail: "Anota movimientos en 20 días de un mismo mes.",
                       current: maxDaysInAMonth, target: 20),
            HabitBadge(id: "first_goal", emoji: "🎯", title: "Primera meta",
                       detail: "Crea una meta de ahorro.",
                       current: input.goals.isEmpty ? 0 : 1, target: 1),
            HabitBadge(id: "saver_4", emoji: "🐷", title: "Ahorro constante",
                       detail: "4 semanas seguidas con un aporte que madura.",
                       current: bestSavingsRun, target: 4),
            HabitBadge(id: "saver_12", emoji: "🏦", title: "Ahorrador de hierro",
                       detail: "12 semanas seguidas con un aporte que madura.",
                       current: bestSavingsRun, target: 12),
            HabitBadge(id: "goal_done", emoji: "🏆", title: "Meta cumplida",
                       detail: "Completa una meta solo con aportes maduros.",
                       current: completedGoal ? 1 : 0, target: 1),
            HabitBadge(id: "budget_1", emoji: "✅", title: "Presupuesto cumplido",
                       detail: "Termina un periodo sin pasarte de un presupuesto.",
                       current: budgetPeriodsMet.count, target: 1),
            HabitBadge(id: "budget_3", emoji: "🧭", title: "Disciplina",
                       detail: "Cumple 3 presupuestos mensuales.",
                       current: monthlyBudgetsMet, target: 3),
            HabitBadge(id: "receipt_1", emoji: "🧾", title: "Factura verificada",
                       detail: "Escanea una factura que se verifique.",
                       current: input.verifiedReceiptDates.count, target: 1),
            HabitBadge(id: "receipt_10", emoji: "🔎", title: "Cazador de facturas",
                       detail: "10 facturas verificadas.",
                       current: input.verifiedReceiptDates.count, target: 10),
        ]
    }

    private func longestConsecutiveWeeks(_ weekStarts: [Date]) -> Int {
        var best = 0
        var run = 0
        var previous: Date?
        for week in Set(weekStarts).sorted() {
            if let previous, add(.weekOfYear, 1, to: previous) == week {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        return best
    }

    // MARK: Utilidades

    private func startOf(_ unit: Calendar.Component, for date: Date) -> Date {
        calendar.dateInterval(of: unit, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func add(_ unit: Calendar.Component, _ value: Int, to date: Date) -> Date {
        calendar.date(byAdding: unit, value: value, to: date) ?? date
    }

    private func addDays(_ days: Int, to date: Date) -> Date {
        add(.day, days, to: date)
    }
}

struct HabitBadge: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    let current: Int
    let target: Int

    var isEarned: Bool { current >= target }
    var progress: Double { target > 0 ? min(1, Double(current) / Double(target)) : 0 }
}

struct HabitLevel: Equatable {
    let number: Int
    let name: String
    let emoji: String
    let minXP: Int
    /// nil en el ultimo nivel.
    let nextLevelXP: Int?

    private static let table: [(name: String, emoji: String, minXP: Int)] = [
        ("Semilla", "🌱", 0),
        ("Brote", "🌿", 100),
        ("Constante", "📅", 250),
        ("Ahorrador", "🐷", 500),
        ("Organizado", "🗂️", 900),
        ("Estratega", "♟️", 1500),
        ("Experto", "💼", 2400),
        ("Maestro", "🏅", 3600),
        ("Leyenda", "🏆", 5200),
        ("Leyenda dorada", "👑", 7500),
    ]

    static func level(forXP xp: Int) -> HabitLevel {
        let index = table.lastIndex { xp >= $0.minXP } ?? 0
        let entry = table[index]
        return HabitLevel(
            number: index + 1,
            name: entry.name,
            emoji: entry.emoji,
            minXP: entry.minXP,
            nextLevelXP: index + 1 < table.count ? table[index + 1].minXP : nil
        )
    }

    /// 0...1 dentro del nivel actual.
    func progress(xp: Int) -> Double {
        guard let next = nextLevelXP, next > minXP else { return 1 }
        return min(1, max(0, Double(xp - minXP) / Double(next - minXP)))
    }
}
