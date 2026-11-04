import Foundation

enum CardBrand: String, Codable, CaseIterable, Identifiable, Hashable {
    case visa
    case mastercard
    case amex
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .other: return "Otra"
        }
    }
}

enum LinkedCardStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case paused
    case removed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Activa"
        case .paused: return "Pausada"
        case .removed: return "Eliminada"
        }
    }
}

/// Tarjeta vinculada para ganar puntos en comercios aliados. Guarda
/// SOLO marca + ultimos 4 + alias — nunca numero completo, CVV ni
/// vencimiento (ver README_SECURITY.md y la migracion
/// 0024_card_linked_offers.sql). Si en el futuro un proveedor real
/// necesita vincular la tarjeta completa, sera con SU componente
/// seguro (SDK/webview del proveedor), nunca con un formulario propio.
struct LinkedCard: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var brand: CardBrand
    var last4: String
    var alias: String
    var status: LinkedCardStatus
    var accountId: UUID?
    let consentAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case brand
        case last4
        case alias
        case status
        case accountId = "account_id"
        case consentAt = "consent_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewLinkedCard: Encodable {
    let userId: UUID
    let brand: CardBrand
    let last4: String
    let alias: String
    let accountId: UUID?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case brand
        case last4
        case alias
        case accountId = "account_id"
    }
}

/// Lo unico que se puede cambiar despues de vincular una tarjeta: su
/// estado (pausar/eliminar) o el alias. Nunca marca/ultimos4 — si esos
/// cambian, es una tarjeta distinta, se vincula de nuevo.
struct LinkedCardStatusUpdate: Encodable {
    let status: LinkedCardStatus
}
