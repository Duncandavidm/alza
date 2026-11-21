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
    /// Dia del mes en que vence el pago (0079). nil si no lo puso.
    var paymentDay: Int?

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
        case paymentDay = "payment_day"
    }

    var dueDateValue: Date? { InvoiceDateFormat.date(from: dueDate) }

    /// Tarjeta de credito: tiene cupo o se llama como una (igual que
    /// debt_is_card en la base).
    var isCard: Bool {
        if (creditLimit ?? 0) > 0 { return true }
        let name = creditor.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return ["tarjeta", "visa", "master", "amex", "american express", "clave", "credito"].contains { name.contains($0) }
    }

    /// Cupo disponible (cupo - lo que se debe). nil sin cupo anotado.
    var availableCredit: Decimal? {
        guard let limit = creditLimit, limit > 0 else { return nil }
        return max(limit - balance, 0)
    }

    /// Pago minimo anotado, o 3% del saldo si no lo puso (como en el
    /// analisis financiero).
    var estimatedMinimum: Decimal {
        if let minimumPayment, minimumPayment > 0 { return min(minimumPayment, balance) }
        return min(FinancialSnapshot.minimum(for: FinancialSnapshot.DebtInput(name: creditor, balance: balance)), balance)
    }
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
    /// Solo viaja si se puso (la columna es de 0079).
    var paymentDay: Int? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case creditor
        case balance
        case creditLimit = "credit_limit"
        case interestRateMonthly = "interest_rate_monthly"
        case minimumPayment = "minimum_payment"
        case dueDate = "due_date"
        case isOverdue = "is_overdue"
        case paymentDay = "payment_day"
    }
}
