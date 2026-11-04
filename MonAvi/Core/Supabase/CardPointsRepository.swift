import Foundation
import Supabase

/// Saldo de puntos confirmados/pendientes (vista `points_balances`,
/// `security_invoker=true` — cada quien solo ve el suyo).
struct PointsBalance: Codable {
    let userId: UUID
    let confirmedPoints: Int
    let pendingPoints: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case confirmedPoints = "confirmed_points"
        case pendingPoints = "pending_points"
    }

    static let zero = PointsBalance(userId: UUID(), confirmedPoints: 0, pendingPoints: 0)
}

/// Datos de "Mis tarjetas" + "Ofertas cerca" + el saldo de puntos
/// (ledger unico, ver migracion 0023_points_ledger.sql).
@MainActor
final class CardPointsRepository {
    static let shared = CardPointsRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    func fetchLinkedCards(userId: UUID) async throws -> [LinkedCard] {
        try await supabase
            .from("linked_cards")
            .select()
            .eq("user_id", value: userId)
            .neq("status", value: LinkedCardStatus.removed.rawValue)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func addLinkedCard(_ new: NewLinkedCard) async throws -> LinkedCard {
        try await supabase
            .from("linked_cards")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
    }

    func updateStatus(_ card: LinkedCard, to status: LinkedCardStatus) async throws {
        try await supabase
            .from("linked_cards")
            .update(LinkedCardStatusUpdate(status: status))
            .eq("id", value: card.id)
            .execute()
    }

    func fetchActiveOffers() async throws -> [PartnerOffer] {
        let merchants: [PartnerMerchant] = try await supabase
            .from("partner_merchants")
            .select()
            .eq("status", value: "active")
            .order("name", ascending: true)
            .execute()
            .value

        let offers: [PartnerMerchantOffer] = try await supabase
            .from("partner_merchant_offers")
            .select()
            .eq("status", value: "active")
            .execute()
            .value
        let offersByMerchant = Dictionary(grouping: offers, by: \.merchantId)

        let now = Date()
        return merchants.map { merchant in
            let currentOffer = offersByMerchant[merchant.id]?.first { offer in
                offer.startsAt <= now && (offer.endsAt == nil || offer.endsAt! >= now)
            }
            return PartnerOffer(merchant: merchant, offer: currentOffer)
        }
    }

    func fetchBalance(userId: UUID) async -> PointsBalance {
        let row: PointsBalance? = try? await supabase
            .from("points_balances")
            .select()
            .eq("user_id", value: userId)
            .maybeSingle()
            .execute()
            .value
        return row ?? PointsBalance(userId: userId, confirmedPoints: 0, pendingPoints: 0)
    }

    /// Para la etiqueta "+X puntos" en el historial de "Hoy": que
    /// transacciones del dia ganaron puntos por tarjeta (fuente unica
    /// por ahora — "Facturas que suman" todavia no tiene su propio
    /// verificador conectado al ledger). Mismo patron gte/lt sobre
    /// `occurred_at` que `TransactionsRepository.fetchDay`.
    func pointsByTransaction(userId: UUID, day: Date) async -> [UUID: Int] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }

        struct Row: Decodable {
            let transactionId: UUID?
            let pointsAwarded: Int?
            enum CodingKeys: String, CodingKey {
                case transactionId = "transaction_id"
                case pointsAwarded = "points_awarded"
            }
        }
        let rows: [Row] = (try? await supabase
            .from("card_transactions")
            .select("transaction_id, points_awarded")
            .eq("user_id", value: userId)
            .gte("occurred_at", value: start)
            .lt("occurred_at", value: end)
            .execute()
            .value) ?? []

        var result: [UUID: Int] = [:]
        for row in rows {
            guard let transactionId = row.transactionId, let points = row.pointsAwarded else { continue }
            result[transactionId] = points
        }
        return result
    }
}
