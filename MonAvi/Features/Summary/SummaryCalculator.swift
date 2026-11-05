import Foundation

/// Que se esta resumiendo: lo que sale o lo que entra.
enum SummaryKind: String, CaseIterable, Identifiable {
    case expenses
    case income

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expenses: return "Gastos"
        case .income: return "Ingresos"
        }
    }

    /// Transferencias e inversiones no son gasto ni ingreso real (el dinero
    /// sigue siendo tuyo), asi que no entran a ninguno de los dos.
    func includes(_ type: MovementType) -> Bool {
        switch self {
        case .expenses: return type == .gasto || type == .pagoProveedor
        case .income: return type == .ingreso
        }
    }

    /// Para pintar la variacion: subir en ingresos es bueno, en gastos no.
    var increaseIsGood: Bool { self == .income }
}

enum SummaryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case quarter
    case last6Months
    case yearToDate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "Semanal"
        case .month: return "Mensual"
        case .quarter: return "Trimestral"
        case .last6Months: return "Últimos 6 meses"
        case .yearToDate: return "Año hasta la fecha"
        }
    }

    /// De que tamaño es cada barra de la grafica.
    var bucketComponent: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        case .last6Months, .yearToDate: return .month
        }
    }
}

/// Una barra de la grafica.
struct SummaryBucket: Identifiable, Equatable {
    let interval: DateInterval
    let label: String
    let total: Decimal

    var id: Date { interval.start }
}

/// Una rebanada de la torta / una fila de la lista por categoria.
struct SummaryCategoryTotal: Identifiable, Equatable {
    /// El texto guardado en `transactions.category` (o "Sin categoría").
    let key: String
    let total: Decimal
    let count: Int
    let previousTotal: Decimal

    var id: String { key }

    var category: TransactionCategory? { TransactionCategory(rawValue: key) }
    var emoji: String { category?.emoji ?? "🏷️" }

    var deltaPercent: Decimal? {
        SummarySnapshot.percentChange(from: previousTotal, to: total)
    }
}

struct SummarySnapshot: Equatable {
    let kind: SummaryKind
    let period: SummaryPeriod
    let interval: DateInterval
    let previousInterval: DateInterval
    /// Movimientos del periodo, ya filtrados por tipo y cuenta, del mas
    /// reciente al mas antiguo.
    let transactions: [FinanceTransaction]
    let buckets: [SummaryBucket]
    let categories: [SummaryCategoryTotal]
    let total: Decimal
    let previousTotal: Decimal
    /// Promedio por barra, contando solo las barras que ya empezaron (los
    /// dias que faltan del mes no deben bajar el promedio).
    let averagePerBucket: Decimal
    let title: String
    let comparisonLabel: String

    var deltaPercent: Decimal? {
        Self.percentChange(from: previousTotal, to: total)
    }

    func share(of item: SummaryCategoryTotal) -> Decimal {
        guard total > 0 else { return 0 }
        return item.total / total * 100
    }

    static func percentChange(from previous: Decimal, to current: Decimal) -> Decimal? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }
}

/// Todos los calculos del Resumen, sin red ni UI, para poder probarlos.
struct SummaryCalculator {
    static let uncategorizedKey = "Sin categoría"

    var calendar: Calendar = .current
    var now: Date = Date()

    // MARK: - Rangos de fechas

    /// El periodo a mostrar. `offset` 0 es el actual, -1 el anterior, etc.
    func interval(for period: SummaryPeriod, offset: Int) -> DateInterval {
        switch period {
        case .week:
            return shifted(unit: .weekOfYear, length: 1, offset: offset)
        case .month:
            return shifted(unit: .month, length: 1, offset: offset)
        case .quarter:
            let monthStart = startOf(.month, for: now)
            let month = calendar.component(.month, from: monthStart)
            let quarterStart = add(.month, -((month - 1) % 3), to: monthStart)
            let start = add(.month, 3 * offset, to: quarterStart)
            return DateInterval(start: start, end: add(.month, 3, to: start))
        case .last6Months:
            let monthStart = startOf(.month, for: now)
            let end = add(.month, 1 + 6 * offset, to: monthStart)
            return DateInterval(start: add(.month, -6, to: end), end: end)
        case .yearToDate:
            // Mismo tramo del año (1 ene -> hoy) para que la comparacion
            // contra años anteriores sea justa.
            let yearStart = startOf(.year, for: now)
            let elapsed = max(now.timeIntervalSince(yearStart), 1)
            let start = add(.year, offset, to: yearStart)
            let end = min(start.addingTimeInterval(elapsed), add(.year, 1, to: start))
            return DateInterval(start: start, end: end)
        }
    }

    /// Corta el periodo en barras alineadas a dias, semanas o meses.
    func bucketIntervals(for period: SummaryPeriod, in interval: DateInterval) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end && result.count < 400 {
            let naturalEnd = calendar.dateInterval(of: period.bucketComponent, for: cursor)?.end ?? interval.end
            let next = min(naturalEnd, interval.end)
            guard next > cursor else { break }
            result.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return result
    }

    // MARK: - Snapshot

    func snapshot(
        transactions all: [FinanceTransaction],
        kind: SummaryKind,
        period: SummaryPeriod,
        offset: Int,
        accountId: UUID?
    ) -> SummarySnapshot {
        let current = interval(for: period, offset: offset)
        let previous = interval(for: period, offset: offset - 1)

        let relevant = all.filter { transaction in
            kind.includes(transaction.movementType)
                && (accountId == nil || transaction.accountId == accountId)
        }
        let inCurrent = relevant
            .filter { contains(current, $0.occurredAt) }
            .sorted { $0.occurredAt > $1.occurredAt }
        let inPrevious = relevant.filter { contains(previous, $0.occurredAt) }

        let buckets = bucketIntervals(for: period, in: current).map { bucket in
            SummaryBucket(
                interval: bucket,
                label: bucketLabel(for: bucket, period: period),
                total: sum(inCurrent.filter { contains(bucket, $0.occurredAt) })
            )
        }

        let total = sum(inCurrent)
        let startedBuckets = buckets.filter { $0.interval.start <= now }.count
        let average = startedBuckets > 0 ? total / Decimal(startedBuckets) : 0

        return SummarySnapshot(
            kind: kind,
            period: period,
            interval: current,
            previousInterval: previous,
            transactions: inCurrent,
            buckets: buckets,
            categories: categoryTotals(current: inCurrent, previous: inPrevious, kind: kind),
            total: total,
            previousTotal: sum(inPrevious),
            averagePerBucket: average,
            title: title(for: period, interval: current),
            comparisonLabel: comparisonLabel(for: period, previous: previous)
        )
    }

    func categoryKey(for transaction: FinanceTransaction, kind: SummaryKind) -> String {
        if let category = transaction.category?.trimmingCharacters(in: .whitespaces), !category.isEmpty {
            return category
        }
        return kind == .income ? TransactionCategory.income.rawValue : Self.uncategorizedKey
    }

    private func categoryTotals(
        current: [FinanceTransaction],
        previous: [FinanceTransaction],
        kind: SummaryKind
    ) -> [SummaryCategoryTotal] {
        let currentGroups = Dictionary(grouping: current) { categoryKey(for: $0, kind: kind) }
        let previousGroups = Dictionary(grouping: previous) { categoryKey(for: $0, kind: kind) }

        return currentGroups.map { key, items in
            SummaryCategoryTotal(
                key: key,
                total: sum(items),
                count: items.count,
                previousTotal: sum(previousGroups[key] ?? [])
            )
        }
        .filter { $0.total > 0 }
        .sorted { lhs, rhs in
            lhs.total != rhs.total ? lhs.total > rhs.total : lhs.key < rhs.key
        }
    }

    // MARK: - Textos

    func bucketLabel(for bucket: DateInterval, period: SummaryPeriod) -> String {
        let format: String
        switch period {
        case .week: format = "EEE"
        case .month: format = "d"
        case .quarter: format = "d MMM"
        case .last6Months, .yearToDate: format = "MMM"
        }
        return formatted(bucket.start, format).replacingOccurrences(of: ".", with: "").capitalized
    }

    func title(for period: SummaryPeriod, interval: DateInterval) -> String {
        let lastInstant = interval.end.addingTimeInterval(-1)
        switch period {
        case .week:
            return "\(formatted(interval.start, "d MMM")) – \(formatted(lastInstant, "d MMM"))"
        case .month:
            return formatted(interval.start, "MMMM yyyy").capitalized
        case .quarter:
            let quarter = (calendar.component(.month, from: interval.start) - 1) / 3 + 1
            return "T\(quarter) \(calendar.component(.year, from: interval.start))"
        case .last6Months:
            return "\(formatted(interval.start, "MMM")) – \(formatted(lastInstant, "MMM yyyy"))"
                .replacingOccurrences(of: ".", with: "").capitalized
        case .yearToDate:
            return "\(calendar.component(.year, from: interval.start)) hasta el \(formatted(lastInstant, "d MMM"))"
                .replacingOccurrences(of: ".", with: "")
        }
    }

    /// Titulo largo de una barra seleccionada ("Lunes 14 de septiembre").
    func selectionTitle(for bucket: DateInterval, period: SummaryPeriod) -> String {
        switch period.bucketComponent {
        case .day:
            return capitalizedFirst(formatted(bucket.start, "EEEE d 'de' MMMM"))
        case .weekOfYear:
            return "Semana del \(formatted(bucket.start, "d MMM"))".replacingOccurrences(of: ".", with: "")
        default:
            return formatted(bucket.start, "MMMM yyyy").capitalized
        }
    }

    /// Encabezado de cada dia en la lista de movimientos.
    func dayTitle(for day: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Hoy" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Ayer"
        }
        return capitalizedFirst(formatted(day, "EEEE, d MMM")).replacingOccurrences(of: ".", with: "")
    }

    func comparisonLabel(for period: SummaryPeriod, previous: DateInterval) -> String {
        switch period {
        case .week: return "vs semana anterior"
        case .month: return "frente a \(formatted(previous.start, "MMMM"))"
        case .quarter: return "vs trimestre anterior"
        case .last6Months: return "vs 6 meses anteriores"
        case .yearToDate: return "vs mismo periodo de \(calendar.component(.year, from: previous.start))"
        }
    }

    // MARK: - Utilidades

    private func sum(_ transactions: [FinanceTransaction]) -> Decimal {
        transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    /// Intervalo semiabierto [start, end): un movimiento a la medianoche
    /// exacta del dia 1 cae en el mes nuevo, no en los dos.
    private func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    private func shifted(unit: Calendar.Component, length: Int, offset: Int) -> DateInterval {
        let start = add(unit, offset * length, to: startOf(unit, for: now))
        return DateInterval(start: start, end: add(unit, length, to: start))
    }

    private func startOf(_ unit: Calendar.Component, for date: Date) -> Date {
        calendar.dateInterval(of: unit, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func add(_ unit: Calendar.Component, _ value: Int, to date: Date) -> Date {
        calendar.date(byAdding: unit, value: value, to: date) ?? date
    }

    private func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

extension Decimal {
    /// Para Swift Charts, que grafica Double.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
