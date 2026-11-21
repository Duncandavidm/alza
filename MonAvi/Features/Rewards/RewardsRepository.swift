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
            .eq("status", value: "active")
            .order("sort_order", ascending: true)
            .execute()
            .value
        return RewardsMath.sorted(RewardsMath.available(items))
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

    /// Categorias del panel (emoji y orden). Si falla, lista vacia: los
    /// chips salen igual, solo sin emoji y en orden alfabetico.
    func fetchCategoriesOrEmpty() async -> [MerchantCategory] {
        let rows: [MerchantCategory]? = try? await supabase
            .from("merchant_categories")
            .select("name, emoji, sort_order")
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows ?? []
    }

    // MARK: - Descuentos de aliados (0067)

    /// Descuentos gratis "por ser de MonAvi" con el estado de esta persona
    /// (desbloqueado, usos del periodo, codigo vigente). La RLS no los
    /// muestra en `reward_items`: solo llegan por esta RPC.
    func fetchBenefits() async throws -> BenefitsResponse {
        try await supabase
            .rpc("my_benefits")
            .execute()
            .value
    }

    /// Si falla (sin red o servidor viejo) no hay descuentos que mostrar.
    func fetchBenefitsOrEmpty() async -> BenefitsResponse {
        (try? await fetchBenefits()) ?? .empty
    }

    /// Genera el codigo de 15 minutos (o devuelve el que ya estaba
    /// vigente). Lanza el mensaje en espanol de la RPC ("Escanea tu primera
    /// factura...", "Ya usaste este descuento esta semana...").
    func useBenefit(item: RewardItem) async throws -> RewardRedemption {
        var redemption: RewardRedemption = try await supabase
            .rpc("use_benefit", params: RedeemParams(pItemId: item.id))
            .execute()
            .value
        redemption.item = item
        redemption.merchant = item.merchant
        return redemption
    }

    /// Canjes propios, del mas nuevo al mas viejo.
    func fetchMyRedemptions(userId: UUID) async throws -> [RewardRedemption] {
        let rows: [RewardRedemption] = try await supabase
            .from("reward_redemptions")
            .select("*, reward_items(*, partner_merchants(*)), partner_merchants(*)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return await fillingMissingItems(RewardsMath.historyRows(rows))
    }

    /// Si un producto se agoto o se pauso despues del canje, la RLS lo
    /// esconde y el embed llega en null ("tu producto"). Se completan con
    /// `my_redemption_items` (migracion 0066), que devuelve solo los
    /// productos que esta persona ya canjeo (sin el comercio embebido: el
    /// canje ya trae el suyo por `merchant_id`). Si falla, se quedan como
    /// venian.
    private func fillingMissingItems(_ rows: [RewardRedemption]) async -> [RewardRedemption] {
        guard rows.contains(where: { $0.item == nil }) else { return rows }
        guard
            let items: [RewardItem] = try? await supabase
                .rpc("my_redemption_items")
                .execute()
                .value
        else { return rows }
        return RewardsMath.fillingMissingItems(rows, with: items)
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
        return RewardsMath.activeGifts(await fillingMissingItems(rows))
    }

    /// Tolerante a fallas (para "Hoy"): cualquier error devuelve [] y la
    /// tarjeta de regalos simplemente no se muestra.
    func fetchActiveGiftsOrEmpty(userId: UUID) async -> [RewardRedemption] {
        (try? await fetchActiveGifts(userId: userId)) ?? []
    }

    /// true si la RPC rechazo el canje porque el correo no esta verificado
    /// ("Verifica tu correo para canjear"): en vez de una alerta, se abre
    /// EmailVerificationSheet y luego se reintenta el canje.
    static func requiresEmailVerification(_ error: Error) -> Bool {
        if let postgrestError = error as? PostgrestError,
           EmailVerificationLogic.isVerificationRequired(message: postgrestError.message) {
            return true
        }
        return EmailVerificationLogic.isVerificationRequired(message: userMessage(for: error))
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
