import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking
    case savings
    case creditCard = "credit_card"
    case investment
    case cash
    case loan
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checking: return "Cuenta de cheques"
        case .savings: return "Ahorro"
        case .creditCard: return "Tarjeta de credito"
        case .investment: return "Inversion"
        case .cash: return "Efectivo"
        case .loan: return "Prestamo"
        case .other: return "Otra"
        }
    }
}

struct Account: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var type: AccountType
    var balance: Decimal
    var currency: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case balance
        case currency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Payload para crear una cuenta (sin campos generados por la base).
struct NewAccount: Encodable {
    let userId: UUID
    let name: String
    let type: AccountType
    let balance: Decimal
    let currency: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case type
        case balance
        case currency
    }
}
