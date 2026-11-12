import Foundation
import SwiftUI

/// Tipos de movimiento claramente diferenciados, como pedia la mejora del
/// "cuaderno del dia": el dueño ya no solo ve +/-, ve QUE TIPO de cosa fue.
enum MovementType: String, Codable, CaseIterable, Identifiable, Hashable {
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
        case .inversion: return "Inversión"
        case .transferencia: return "Transferencia"
        }
    }

    /// true = entra dinero, false = sale dinero de la cuenta.
    var isInflow: Bool { self == .ingreso }

    /// Los unicos tipos que ofrece "Anotar movimiento". "Pago a proveedor"
    /// y "Transferencia" se siguen pudiendo leer (datos viejos), pero ahora
    /// se anotan como gasto con categoria Proveedores / Transferencias.
    static let quickAddTypes: [MovementType] = [.ingreso, .gasto, .inversion]

    /// Tipo + categoria con que se muestra/guarda en "Anotar movimiento":
    /// pago_proveedor → gasto + Proveedores, transferencia → gasto +
    /// Transferencias; los demas quedan igual (sin categoria forzada).
    var quickAddMapping: (movementType: MovementType, category: TransactionCategory?) {
        switch self {
        case .pagoProveedor: return (.gasto, .suppliers)
        case .transferencia: return (.gasto, .transfers)
        case .ingreso, .gasto, .inversion: return (self, nil)
        }
    }

    var tintColor: Color {
        isInflow ? MonAviBrand.primary : MonAviBrand.alert
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

enum TransactionCategory: String, CaseIterable, Identifiable, Hashable {
    // Los rawValue son lo que se guarda en la columna `category` (y en
    // budgets.category): NO cambiarlos, solo agregar nuevos.
    case income = "Ingreso"
    case housing = "Vivienda"
    case food = "Comida"
    case groceries = "Supermercado"
    case utilities = "Servicios"
    case transport = "Transporte"
    case shopping = "Compras"
    case clothing = "Ropa"
    case goingOut = "Salir"
    case entertainment = "Entretenimiento"
    case subscriptions = "Suscripciones"
    case health = "Salud"
    case education = "Educación"
    case pets = "Mascotas"
    case gifts = "Regalos"
    case travel = "Viajes"
    case savings = "Ahorro"
    /// Antes era el tipo de movimiento "Pago a proveedor"; ahora es un
    /// gasto con esta categoria (ver MovementType.quickAddMapping).
    case suppliers = "Proveedores"
    /// Antes era el tipo de movimiento "Transferencia"; ahora es un gasto
    /// con esta categoria.
    case transfers = "Transferencias"
    case other = "Otro"

    var id: String { rawValue }

    /// Se usa como el "producto" que cae en el carrito de CartLoadingView
    /// al guardar un movimiento, y como icono en listas y graficas.
    var emoji: String {
        switch self {
        case .income: return "💰"
        case .housing: return "🏠"
        case .food: return "🍔"
        case .groceries: return "🛒"
        case .utilities: return "💡"
        case .transport: return "🚗"
        case .shopping: return "🛍️"
        case .clothing: return "👕"
        case .goingOut: return "🍻"
        case .entertainment: return "🎬"
        case .subscriptions: return "📺"
        case .health: return "🩺"
        case .education: return "📚"
        case .pets: return "🐾"
        case .gifts: return "🎁"
        case .travel: return "✈️"
        case .savings: return "💵"
        case .suppliers: return "🏭"
        case .transfers: return "🔁"
        case .other: return "📦"
        }
    }

    /// Color de la categoria en la grafica de torta y en los iconos. Paleta
    /// anclada en el teal de marca (#00A585), con tonos vivos pero
    /// distinguibles entre si para que la torta se lea de un vistazo.
    var color: Color {
        let hex: String
        switch self {
        case .income: hex = "#00A585"
        case .housing: hex = "#00A585"
        case .food: hex = "#F4A07A"
        case .groceries: hex = "#F2C14E"
        case .utilities: hex = "#4A90E2"
        case .transport: hex = "#E85D75"
        case .shopping: hex = "#B37FEB"
        case .clothing: hex = "#5BC0BE"
        case .goingOut: hex = "#FF8C42"
        case .entertainment: hex = "#D65DB1"
        case .subscriptions: hex = "#7A86E8"
        case .health: hex = "#2BB673"
        case .education: hex = "#3D7EA6"
        case .pets: hex = "#C49A6C"
        case .gifts: hex = "#F28AB2"
        case .travel: hex = "#36B5D8"
        case .savings: hex = "#027A64"
        case .suppliers: hex = "#8D6E63"
        case .transfers: hex = "#5C7CFA"
        case .other: hex = "#9AA5A1"
        }
        return Color(hex: hex) ?? .gray
    }
}
