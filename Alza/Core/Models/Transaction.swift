import Foundation
import SwiftUI

/// Tipos de movimiento claramente diferenciados, como pedia la mejora del
/// "cuaderno del dia": el dueño ya no solo ve +/-, ve QUE TIPO de cosa fue.
enum MovementType: String, Codable, CaseIterable, Identifiable {
    case ingreso
    case gasto
    case pagoProveedor = "pago_proveedor"
    case inversion
    case transferencia

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .ingreso: return "💰"
        case .gasto: return "💸"
        case .pagoProveedor: return "🏭"
        case .inversion: return "📈"
        case .transferencia: return "💳"
        }
    }

    var displayName: String {
        switch self {
        case .ingreso: return "Ingreso"
        case .gasto: return "Gasto"
        case .pagoProveedor: return "Pago a proveedor"
        case .inversion: return "Inversion"
        case .transferencia: return "Transferencia"
        }
    }

    /// true = entra dinero, false = sale dinero de la cuenta.
    var isInflow: Bool { self == .ingreso }

    var tintColor: Color {
        isInflow ? .green : .red
    }

    /// Normaliza el monto que escribe el usuario (siempre positivo en la UI)
    /// al signo que se guarda en la base (positivo = entra, negativo = sale).
    func signedAmount(from magnitude: Decimal) -> Decimal {
        isInflow ? abs(magnitude) : -abs(magnitude)
    }
}

/// amount positivo = entra dinero, negativo = sale dinero (mismo signo que
/// antes; movementType agrega el "que tipo de cosa fue" sin cambiar esa
/// convencion).
struct FinanceTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let accountId: UUID
    var amount: Decimal
    var movementType: MovementType
    var category: String?
    var description: String?
    var tags: [String]
    /// Si el movimiento se origino en otra moneda (conversion automatica,
    /// inspirado en MonAi), aqui queda el registro de esa moneda/monto
    /// original. `amount` siempre queda en la moneda de la cuenta.
    var originalCurrency: String?
    var originalAmount: Decimal?
    var occurredAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case amount
        case movementType = "movement_type"
        case category
        case description
        case tags
        case originalCurrency = "original_currency"
        case originalAmount = "original_amount"
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
    }
}

struct NewTransaction: Encodable {
    let userId: UUID
    let accountId: UUID
    let amount: Decimal
    let movementType: MovementType
    let category: String?
    let description: String?
    var tags: [String] = []
    var originalCurrency: String?
    var originalAmount: Decimal?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case amount
        case movementType = "movement_type"
        case category
        case description
        case tags
        case originalCurrency = "original_currency"
        case originalAmount = "original_amount"
        case occurredAt = "occurred_at"
    }
}

enum TransactionCategory: String, CaseIterable, Identifiable {
    case income = "Ingreso"
    case housing = "Vivienda"
    case food = "Comida"
    case transport = "Transporte"
    case entertainment = "Entretenimiento"
    case health = "Salud"
    case savings = "Ahorro"
    case other = "Otro"

    var id: String { rawValue }

    /// Se usa como el "producto" que cae en el carrito de CartLoadingView
    /// al guardar un movimiento.
    var emoji: String {
        switch self {
        case .income: return "💰"
        case .housing: return "🏠"
        case .food: return "🍔"
        case .transport: return "🚗"
        case .entertainment: return "🎬"
        case .health: return "🩺"
        case .savings: return "💵"
        case .other: return "🛍️"
        }
    }
}
