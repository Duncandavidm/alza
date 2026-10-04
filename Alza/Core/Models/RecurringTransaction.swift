import Foundation

/// Movimiento fijo que se repite cada mes (renta, Netflix, gimnasio...).
/// Inspirado en "Crea transacciones recurrentes para que nunca olvides
/// nada" — muy cercano al gastos_fijos_config del plan original de Avi.
struct RecurringTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var accountId: UUID
    var name: String
    var amount: Decimal
    var movementType: MovementType
    var category: String?
    var dayOfMonth: Int
    var active: Bool
    var lastLoggedOn: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case movementType = "movement_type"
        case category
        case dayOfMonth = "day_of_month"
        case active
        case lastLoggedOn = "last_logged_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// true si hoy es su dia y todavia no se registro este mes.
    func isDueToday(calendar: Calendar = .current, today: Date = Date()) -> Bool {
        guard active else { return false }
        guard calendar.component(.day, from: today) == dayOfMonth else { return false }
        guard let lastLoggedOn else { return true }
        return !calendar.isDate(lastLoggedOn, equalTo: today, toGranularity: .month)
    }
}

struct NewRecurringTransaction: Encodable {
    let userId: UUID
    let accountId: UUID
    let name: String
    let amount: Decimal
    let movementType: MovementType
    let category: String?
    let dayOfMonth: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case name
        case amount
        case movementType = "movement_type"
        case category
        case dayOfMonth = "day_of_month"
    }
}
