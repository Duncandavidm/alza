import Foundation

enum DebtStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case inRestructuring = "in_restructuring"
    case paidOff = "paid_off"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Activa"
        case .inRestructuring: return "En reestructuracion"
        case .paidOff: return "Pagada"
        }
    }
}

/// Tarjetas de credito, prestamos, sobregiros — deudas con tasa de
/// interes y posible mora, que `prioritize-payments` toma en cuenta junto
/// a las cuentas por pagar y los recurrentes vencidos.
struct Debt: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var creditor: String
    var balance: Decimal
    var creditLimit: Decimal?
    var interestRateMonthly: Decimal?
    var minimumPayment: Decimal?
    var dueDate: String?
    var isOverdue: Bool
    var status: DebtStatus
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case creditor
        case balance
        case creditLimit = "credit_limit"
        case interestRateMonthly = "interest_rate_monthly"
        case minimumPayment = "minimum_payment"
        case dueDate = "due_date"
        case isOverdue = "is_overdue"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var dueDateValue: Date? { InvoiceDateFormat.date(from: dueDate) }
}

struct NewDebt: Encodable {
    let userId: UUID
    let creditor: String
    let balance: Decimal
    let creditLimit: Decimal?
    let interestRateMonthly: Decimal?
    let minimumPayment: Decimal?
    let dueDate: String?
    let isOverdue: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case creditor
        case balance
        case creditLimit = "credit_limit"
        case interestRateMonthly = "interest_rate_monthly"
        case minimumPayment = "minimum_payment"
        case dueDate = "due_date"
        case isOverdue = "is_overdue"
    }
}
