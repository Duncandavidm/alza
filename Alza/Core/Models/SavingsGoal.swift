import Foundation

/// Mismo patron que BillDateFormat/InvoiceDateFormat: la columna `date` de
/// Postgres se maneja como String "yyyy-MM-dd" de punta a punta.
enum SavingsGoalDateFormat {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }
}

/// Meta de ahorro a corto/largo plazo ("Carro nuevo", $15,000, para
/// diciembre de 2026) — la cuota mensual necesaria NO se guarda, se
/// recalcula siempre de `targetAmount`, `currentAmount` y `targetDate`,
/// para que mover la fecha o aportar dinero actualice el numero solo.
struct SavingsGoal: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var emoji: String
    var targetAmount: Decimal
    var targetDate: String
    var currentAmount: Decimal
    var accountId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case emoji
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case currentAmount = "current_amount"
        case accountId = "account_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var targetDateValue: Date { SavingsGoalDateFormat.date(from: targetDate) }

    var remainingAmount: Decimal { max(0, targetAmount - currentAmount) }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: currentAmount / targetAmount).doubleValue)
    }

    var isAchieved: Bool { currentAmount >= targetAmount }

    var isPastDue: Bool {
        !isAchieved && Calendar.current.startOfDay(for: targetDateValue) < Calendar.current.startOfDay(for: Date())
    }

    /// Meses hasta la fecha limite, redondeando CUALQUIER fraccion hacia
    /// arriba (ej. "faltan 2 meses y 10 dias" cuenta como 3) — para que la
    /// cuota sugerida alcance de sobra en vez de quedarse corta, y nunca
    /// menos de 1 (si ya vencio o es este mes, se pide todo de una vez).
    var monthsRemaining: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: targetDateValue)
        guard end > start else { return 1 }

        let components = calendar.dateComponents([.month, .day], from: start, to: end)
        let months = components.month ?? 0
        let extraDay = (components.day ?? 0) > 0 ? 1 : 0
        return max(1, months + extraDay)
    }

    /// Cuanto hay que aportar cada mes para llegar a la meta a tiempo.
    var monthlyContributionNeeded: Decimal {
        guard !isAchieved else { return 0 }
        return remainingAmount / Decimal(monthsRemaining)
    }
}

struct NewSavingsGoal: Encodable {
    let userId: UUID
    let name: String
    let emoji: String
    let targetAmount: Decimal
    let targetDate: String
    let accountId: UUID?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case emoji
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case accountId = "account_id"
    }
}
