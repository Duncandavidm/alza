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
        guard let row else {
            self = .none
            return
        }
        switch row.status {
        case "active":
            self = .active(expiresAt: row.expiresAt)
        case "in_grace_period":
            self = .inGracePeriod(expiresAt: row.expiresAt)
        case "expired":
            self = .expired
        case "revoked":
            self = .revoked
        default:
            self = .unknown
        }
    }
}
