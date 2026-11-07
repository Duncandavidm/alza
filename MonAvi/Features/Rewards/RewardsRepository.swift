import Foundation
import Supabase

/// Catalogo de canje y canjes del usuario (migracion 0031). El canje
/// en si solo se hace por la RPC `redeem_reward`, que valida saldo y
/// descuenta los puntos en una sola transaccion del lado del servidor.
@MainActor
final class RewardsRepository {
    static let shared = RewardsRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    /// Productos activos de comercios activos (la RLS ya filtra), en
    /// orden de comercio y luego `sort_order`. El embed
    /// `partner_merchants(*)` trae `reward_currency` (moneda de canje del
    /// comercio): `points_cost` esta en esa moneda.
    func fetchItems() async throws -> [RewardItem] {
        let items: [RewardItem] = try await supabase
            .from("reward_items")
            .select("*, partner_merchants(*)")
            .order("sort_order", ascending: true)
            .execute()
            .value
        return RewardsMath.sorted(items)
    }

    private struct RedeemParams: Encodable {
        let pItemId: UUID
        enum CodingKeys: String, CodingKey { case pItemId = "p_item_id" }
    }

    /// Lanza el error de Postgres con el mensaje en espanol de la RPC
    /// ("No tienes puntos suficientes", etc.) — ver `userMessage(for:)`.
    func redeem(item: RewardItem) async throws -> RewardRedemption {
        var redemption: RewardRedemption = try await supabase
            .rpc("redeem_reward", params: RedeemParams(pItemId: item.id))
            .execute()
            .value
        redemption.item = item
        redemption.merchant = item.merchant
        return redemption
    }

    /// Canjes propios, del mas nuevo al mas viejo.
    func fetchMyRedemptions(userId: UUID) async throws -> [RewardRedemption] {
        try await supabase
            .from("reward_redemptions")
            .select("*, reward_items(*, partner_merchants(*)), partner_merchants(*)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Regalos de MonAvi listos para usar (emitidos y sin vencer), del
    /// que vence primero al ultimo.
    func fetchActiveGifts(userId: UUID) async throws -> [RewardRedemption] {
        let rows: [RewardRedemption] = try await supabase
            .from("reward_redemptions")
            .select("*, reward_items(*, partner_merchants(*)), partner_merchants(*)")
            .eq("user_id", value: userId)
            .eq("source", value: "regalo")
            .eq("status", value: "emitido")
            .order("expires_at", ascending: true)
            .execute()
            .value
        return RewardsMath.activeGifts(rows)
    }

    /// Tolerante a fallas (para "Hoy"): cualquier error devuelve [] y la
    /// tarjeta de regalos simplemente no se muestra.
    func fetchActiveGiftsOrEmpty(userId: UUID) async -> [RewardRedemption] {
        (try? await fetchActiveGifts(userId: userId)) ?? []
    }

    /// El mensaje que armo la RPC (ya en espanol) si es un error de
    /// Postgres; si no, el texto generico del error.
    static func userMessage(for error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            let message = postgrestError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return message
            }
        }
        return "No se pudo completar el canje. Revisa tu conexión e inténtalo de nuevo."
    }
}
