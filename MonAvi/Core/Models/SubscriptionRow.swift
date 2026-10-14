import Foundation

/// Refleja public.subscriptions, escrita solo por la Edge Function
/// verify-apple-receipt despues de validar el receipt con Apple.
struct SubscriptionRow: Codable, Hashable {
    let userId: UUID
    let productId: String
    let status: String
    let appleTransactionId: String?
    let appleOriginalTransactionId: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case productId = "product_id"
        case status
        case appleTransactionId = "apple_transaction_id"
        case appleOriginalTransactionId = "apple_original_transaction_id"
        case expiresAt = "expires_at"
    }
}

/// Fila que devuelve la RPC get_entitlement_status — la propia suscripcion
/// del usuario si la tiene, o si no, la del dueno del grupo familiar al
/// que pertenece (ver supabase/migrations/0017_family_groups.sql). Vacia
/// (sin filas) significa que no hay ninguna de las dos.
struct EntitlementRow: Decodable, Hashable {
    let status: String
    let productId: String?
    let expiresAt: Date?
    let viaFamily: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case productId = "product_id"
        case expiresAt = "expires_at"
        case viaFamily = "via_family"
    }
}

enum SubscriptionStatus: Equatable {
    case unknown
    case none
    case active(expiresAt: Date?)
    case inGracePeriod(expiresAt: Date?)
    case expired
    case revoked

    var isEntitled: Bool {
        switch self {
        case .active, .inGracePeriod:
            return true
        case .unknown, .none, .expired, .revoked:
            return false
        }
    }

    init(row: SubscriptionRow?) {
        self.init(status: row?.status, expiresAt: row?.expiresAt)
    }

    /// status == nil equivale a "sin fila" (SubscriptionStatus.none) — pasa
    /// cuando no hay suscripcion propia ni membresia de familia activa.
    init(status: String?, expiresAt: Date?) {
        switch status {
        case "active":
            self = .active(expiresAt: expiresAt)
        case "in_grace_period":
            self = .inGracePeriod(expiresAt: expiresAt)
        case "expired":
            self = .expired
        case "revoked":
            self = .revoked
        case nil:
            self = .none
        default:
            self = .unknown
        }
    }
}
