import Foundation

/// «El guardián de tu dinero»: revisa las cuentas y los movimientos y
/// avisa de los peligros con palabras simples. Una cuenta en negativo
/// (se gastó dinero que no hay), un mes en el que sale más de lo que entra,
/// una categoría muy por encima de lo normal, un presupuesto pasado o
/// pagos de la semana que no alcanzan a cubrirse.
/// Lógica pura, sin red: la usa Hoy (y se puede probar sola).
struct MoneyGuard {
    struct Warning: Identifiable, Equatable {
        enum Severity: Int, Comparable {
            case info, caution, danger
            static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        enum Action: Equatable {
            /// Abre «Anotar movimiento» como ingreso en esa cuenta.
            case recordIncome(accountId: UUID?)
            case openBudget(budgetId: UUID)
            case openSpending
            case openBills
        }

        let id: String
        let severity: Severity
        let emoji: String
        let title: String
        let message: String
        var action: Action? = nil
        var actionTitle: String? = nil
    }

    let accounts: [Account]
    /// Movimientos de los ultimos ~4 meses (los de antes no se usan).
    let transactions: [FinanceTransaction]
    var budgets: [BudgetProgress] = []
    var pendingBills: [Bill] = []
    var now: Date = Date()
    var calendar: Calendar = .current
    var country: AppCountry = .current

    /// Montos por debajo de esto no merecen una alerta (centavos, redondeos).
    var minimumAmount: Decimal { country == .colombia ? 20_000 : 5 }

    // MARK: - Resultado

    /// Todas las alertas, de la más grave a la más leve.
    var warnings: [Warning] {
        let all = negativeAccountWarnings
            + monthBalanceWarnings
            + billsWarnings
            + budgetWarnings
            + categorySpikeWarnings
        // sort estable: dentro de la misma gravedad queda el orden de arriba.
        return all.enumerated()
            .sorted { lhs, rhs in
                lhs.element.severity != rhs.element.severity
                    ? lhs.element.severity > rhs.element.severity
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: - Cuentas en negativo

    /// Banco, efectivo, ahorros... en negativo: se anotó un gasto con
    /// dinero que no estaba. Las tarjetas y préstamos no cuentan (su
    /// saldo negativo es lo que se debe).
    var negativeAccounts: [Account] {
        accounts.filter { !$0.type.isLiability && $0.balance < 0 }
    }

    var negativeAccountWarnings: [Warning] {
        negativeAccounts.map { account in
            let money = Self.money(abs(account.balance), currency: account.currency)
            return Warning(
                id: "negative-\(account.id)",
                severity: .danger,
                emoji: "🚨",
                title: "«\(account.name)» está en negativo",
                message: "Quedó en -\(money). No se puede gastar dinero que no hay: ¿te falta anotar un ingreso, o ese gasto salió de otra cuenta o de una tarjeta? Corrígelo para que tus números digan la verdad.",
                action: .recordIncome(accountId: account.id),
                actionTitle: "Anotar el ingreso"
            )
        }
    }

    // MARK: - Lo que entra y lo que sale este mes

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    private func monthInterval(offset: Int) -> DateInterval? {
        guard let date = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return nil }
        return calendar.dateInterval(of: .month, for: date)
    }

    private func isSpending(_ transaction: FinanceTransaction) -> Bool {
        transaction.movementType == .gasto || transaction.movementType == .pagoProveedor
    }

    private func income(in interval: DateInterval) -> Decimal {
        transactions
            .filter { $0.movementType == .ingreso && interval.contains($0.occurredAt) }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    private func spending(in interval: DateInterval) -> Decimal {
        transactions
            .filter { isSpending($0) && interval.contains($0.occurredAt) }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    var monthIncome: Decimal { monthInterval(offset: 0).map(income(in:)) ?? 0 }
    var monthSpending: Decimal { monthInterval(offset: 0).map(spending(in:)) ?? 0 }
    var lastMonthIncome: Decimal { monthInterval(offset: -1).map(income(in:)) ?? 0 }

    /// Con qué ingreso comparar: el de este mes o, si todavía no llega
    /// todo (la quincena del 30), el del mes pasado.
    var referenceIncome: Decimal { max(monthIncome, lastMonthIncome) }

    /// Cuenta principal del día a día, para «Anotar el ingreso».
    private var mainAccountId: UUID? {
        accounts.first { !$0.type.isReserve && !$0.type.isLiability }?.id ?? accounts.first?.id
    }

    var monthBalanceWarnings: [Warning] {
        let spent = monthSpending
        guard spent >= minimumAmount else { return [] }
        let reference = referenceIncome

        if reference <= 0 {
            // Gasta y no hay ni un ingreso anotado en dos meses. Si ya hay
            // una cuenta en negativo, esa alerta lo dice mejor.
            guard negativeAccounts.isEmpty else { return [] }
            return [Warning(
                id: "no-income",
                severity: .caution,
                emoji: "🤔",
                title: "¿De dónde sale el dinero?",
                message: "Este mes llevas \(Self.money(spent)) en gastos y no hay ningún ingreso anotado. Si cobraste, anótalo; si estás usando tus ahorros o la tarjeta, ten cuidado: así el dinero se acaba o la deuda crece.",
                action: .recordIncome(accountId: mainAccountId),
                actionTitle: "Anotar un ingreso"
            )]
        }

        if spent > reference, spent - reference >= minimumAmount {
            return [Warning(
                id: "overspending-month",
                severity: .danger,
                emoji: "🔥",
                title: "Este mes gastas más de lo que te entra",
                message: "Llevas \(Self.money(spent)) en gastos y te entran \(Self.money(reference)): son \(Self.money(spent - reference)) de más. Ese dinero sale de tus ahorros o de deuda. Frena los gastos que no sean necesarios hasta fin de mes.",
                action: .openSpending,
                actionTitle: "Ver en qué se va"
            )]
        }

        // Todavía no se pasa, pero al ritmo que va, sí.
        let day = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        guard day >= 7, day < daysInMonth else { return [] }
        let projected = (spent / Decimal(day) * Decimal(daysInMonth)).roundedTo(0)
        guard projected > reference * Decimal(string: "1.05")!, projected - reference >= minimumAmount else { return [] }
        let perDay = ((reference - spent) / Decimal(daysInMonth - day)).roundedTo(country == .colombia ? 0 : 2)
        return [Warning(
            id: "pace-month",
            severity: .caution,
            emoji: "⏱️",
            title: "A este ritmo no te alcanza el mes",
            message: "Vas en \(Self.money(spent)) y si sigues así terminarías el mes en unos \(Self.money(projected)), más de lo que te entra (\(Self.money(reference))). Para llegar bien, gasta como máximo \(Self.money(max(perDay, 0))) al día lo que queda del mes.",
            action: .openSpending,
            actionTitle: "Ver en qué se va"
        )]
    }

    // MARK: - Pagos de la semana

    /// Lo que hay para gastar hoy: banco y efectivo (sin ahorros ni deudas).
    var availableCash: Decimal {
        max(accounts
            .filter { !$0.type.isReserve && !$0.type.isLiability }
            .reduce(Decimal(0)) { $0 + $1.balance }, 0)
    }

    var billsWarnings: [Warning] {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        let soon = pendingBills.filter { calendar.startOfDay(for: $0.dueDateValue) <= limit && !$0.movementType.isInflow }
        guard !soon.isEmpty else { return [] }
        let total = soon.reduce(Decimal(0)) { $0 + $1.amount }
        let cash = availableCash
        guard total > cash, total - cash >= minimumAmount else { return [] }
        let overdue = soon.filter { calendar.startOfDay(for: $0.dueDateValue) < today }.count
        let count = soon.count == 1 ? "un pago" : "\(soon.count) pagos"
        return [Warning(
            id: "bills-week",
            severity: overdue > 0 ? .danger : .caution,
            emoji: "📅",
            title: "No te alcanza para los pagos de la semana",
            message: "Tienes \(count) por \(Self.money(total))\(overdue > 0 ? " (\(overdue == 1 ? "uno vencido" : "\(overdue) vencidos"))" : "") y solo \(Self.money(cash)) disponible. Paga primero lo esencial (casa, luz, agua, comida) y evita gastos extra hasta cubrirlos.",
            action: .openBills,
            actionTitle: "Ver pagos"
        )]
    }

    // MARK: - Presupuestos pasados

    var budgetWarnings: [Warning] {
        budgets
            .filter { $0.status == .over && $0.spent - $0.budget.limitAmount >= minimumAmount }
            .sorted { ($0.spent - $0.budget.limitAmount) > ($1.spent - $1.budget.limitAmount) }
            .prefix(2)
            .map { progress in
                Warning(
                    id: "budget-\(progress.budget.id)",
                    severity: .caution,
                    emoji: CategoryDisplay.emoji(for: progress.budget.category) ?? "📊",
                    title: "Te pasaste en \(progress.budget.category)",
                    message: "Gastaste \(Self.money(progress.spent)) de \(Self.money(progress.budget.limitAmount)): \(Self.money(progress.spent - progress.budget.limitAmount)) por encima de tu límite. Lo que gastes de más aquí sale de otra cosa.",
                    action: .openBudget(budgetId: progress.budget.id),
                    actionTitle: "Ver presupuesto"
                )
            }
    }

    // MARK: - Categorías muy por encima de lo normal

    struct CategorySpike: Equatable {
        let category: String
        let current: Decimal
        let average: Decimal
        var excess: Decimal { current - average }
        var percentAbove: Int {
            guard average > 0 else { return 0 }
            return Int(NSDecimalNumber(decimal: (current - average) / average * 100).doubleValue.rounded())
        }
    }

    /// Categorías que este mes ya van 40% o más por encima de su promedio
    /// de los 3 meses anteriores (solo meses con movimientos anotados).
    /// Las que ya tienen presupuesto pasado no se repiten.
    var categorySpikes: [CategorySpike] {
        guard let current = monthInterval(offset: 0) else { return [] }
        let previous = (1...3).compactMap { monthInterval(offset: -$0) }
        let monthsWithData = previous.filter { interval in
            transactions.contains { interval.contains($0.occurredAt) }
        }
        guard !monthsWithData.isEmpty else { return [] }

        let ignored: Set<String> = [TransactionCategory.transfers.rawValue]
        let overBudget = Set(budgets.filter { $0.status == .over }.map(\.budget.category))

        func totals(in interval: DateInterval) -> [String: Decimal] {
            Dictionary(grouping: transactions.filter { isSpending($0) && interval.contains($0.occurredAt) }) {
                $0.category ?? "Otro"
            }
            .mapValues { $0.reduce(Decimal(0)) { $0 + abs($1.amount) } }
        }

        let currentTotals = totals(in: current)
        var history: [String: Decimal] = [:]
        for interval in monthsWithData {
            for (category, total) in totals(in: interval) { history[category, default: 0] += total }
        }
        let months = Decimal(monthsWithData.count)

        return currentTotals.compactMap { category, total -> CategorySpike? in
            guard !ignored.contains(category), !overBudget.contains(category),
                  let past = history[category], past > 0 else { return nil }
            let average = (past / months).roundedTo(2)
            guard total > average * Decimal(string: "1.4")!, total - average >= minimumAmount * 4 else { return nil }
            return CategorySpike(category: category, current: total, average: average)
        }
        .sorted { $0.excess > $1.excess }
    }

    var categorySpikeWarnings: [Warning] {
        categorySpikes.prefix(2).map { spike in
            Warning(
                id: "spike-\(spike.category)",
                severity: .caution,
                emoji: CategoryDisplay.emoji(for: spike.category) ?? "📈",
                title: "Mucho gasto en \(spike.category)",
                message: "Este mes llevas \(Self.money(spike.current)), un \(spike.percentAbove)% más que tu promedio (\(Self.money(spike.average)) al mes). ¿Vale la pena? Bájale un poco o ponle un presupuesto.",
                action: .openSpending,
                actionTitle: "Ver detalle"
            )
        }
    }

    // MARK: - Formato

    static func money(_ value: Decimal, currency: String? = nil) -> String {
        if let currency { return value.formatted(.currency(code: currency)) }
        return value.formatted(.appCurrency)
    }
}
