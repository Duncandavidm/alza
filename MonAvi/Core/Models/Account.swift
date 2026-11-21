import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable, Hashable {
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
    /// Tarjeta de credito vinculada a su deuda (0079): gastar con ella sube
    /// la deuda. nil en el resto de cuentas.
    var debtId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case balance
        case currency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case debtId = "debt_id"
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

/// Icono SF Symbol de cada tipo de cuenta (selector de cuenta y "Tus
/// cuentas" en Hoy).
enum AccountIcon {
    static func symbol(for type: AccountType) -> String {
        switch type {
        case .checking: return "building.columns"
        case .savings: return "banknote"
        case .creditCard: return "creditcard"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .cash: return "dollarsign.circle"
        case .loan: return "doc.text"
        case .other: return "wallet.pass"
        }
    }
}

extension AccountType {
    /// Ahorros e inversiones: no se usan por defecto para el gasto del dia.
    var isReserve: Bool { self == .savings || self == .investment }
    /// Tarjetas y prestamos: el saldo es lo que se debe.
    var isLiability: Bool { self == .creditCard || self == .loan }
}

extension Account {
    /// Lo que se ve como saldo: en una tarjeta, cuanto se debe (en
    /// positivo); en el resto, el saldo tal cual. La tarjeta guarda su
    /// saldo en negativo (gastar con ella lo baja), igual que la base.
    var displayAmount: Decimal { type == .creditCard ? abs(balance) : balance }

    var balanceCaption: String {
        switch type {
        case .creditCard: return balance <= 0 ? "Debes" : "A favor"
        case .loan: return "Debes"
        default: return type.displayName
        }
    }
}
