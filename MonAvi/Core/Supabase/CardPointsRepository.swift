import Foundation
import Supabase

/// Saldos del usuario (vista `points_balances`, `security_invoker=true`
/// — cada quien solo ve el suyo). Dos monedas (migracion 0036):
/// - Cashback en centavos (1 = US$0.01): `confirmed_points` (canjeable)
///   y `pending_points` (por confirmar), de facturas verificadas por la DGI.
/// - Puntos por buenos habitos: `habit_points` (saldo canjeable) y
///   `habit_points_earned` (total historico ganado, define el nivel).
struct PointsBalance: Codable {
    let userId: UUID
    /// Cashback disponible, en centavos.
    let confirmedPoints: Int
    /// Cashback por confirmar, en centavos.
    let pendingPoints: Int
    /// Puntos por habitos disponibles para canjear.
    var habitPoints: Int = 0
    /// Puntos por habitos ganados en total (para el nivel).
    var habitPointsEarned: Int = 0

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case confirmedPoints = "confirmed_points"
        case pendingPoints = "pending_points"
        case habitPoints = "habit_points"
        case habitPointsEarned = "habit_points_earned"
    }

    static let zero = PointsBalance(userId: UUID(), confirmedPoints: 0, pendingPoints: 0)

    /// Saldo canjeable en la moneda de un comercio.
    func spendable(in currency: RewardCurrency) -> Int {
        switch currency {
        case .cashback: return confirmedPoints
        case .puntos: return habitPoints
        }
    }
}

extension PointsBalance {
    /// Decodificado tolerante: las columnas nuevas pueden faltar (vista
    /// vieja) o llegar en null -> 0.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        confirmedPoints = try container.decodeIfPresent(Int.self, forKey: .confirmedPoints) ?? 0
        pendingPoints = try container.decodeIfPresent(Int.self, forKey: .pendingPoints) ?? 0
        habitPoints = try container.decodeIfPresent(Int.self, forKey: .habitPoints) ?? 0
        habitPointsEarned = try container.decodeIfPresent(Int.self, forKey: .habitPointsEarned) ?? 0
    }
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
        (try? await fetchBalanceOrThrow(userId: userId))
            ?? PointsBalance(userId: userId, confirmedPoints: 0, pendingPoints: 0)
    }

    /// Igual que `fetchBalance` pero distingue un error de red (lanza)
    /// de un usuario sin movimientos en el ledger (saldo en cero).
    func fetchBalanceOrThrow(userId: UUID) async throws -> PointsBalance {
        let row: PointsBalance? = try await supabase
            .from("points_balances")
            // `*`: trae confirmed/pending (cashback) y habit_points /
            // habit_points_earned (puntos); si alguna falta, decodifica 0.
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

    // MARK: - Habitos (Fase 2)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Tope mensual de puntos de habitos configurado en `points_rules`
    /// (ver migracion 0026) — solo para mostrarlo en la UI; el tope real
    /// lo aplica `award-habit-points` del lado del servidor.
    func habitMonthlyCap() async -> Int {
        struct Row: Decodable { let value: Int }
        let row: Row? = try? await supabase
            .from("points_rules")
            .select("value")
            .eq("source", value: "habito")
            .eq("key", value: "monthly_cap_points")
            .maybeSingle()
            .execute()
            .value
        return row?.value ?? 200
    }

    func habitPointsThisMonth(userId: UUID) async -> Int {
        struct Row: Decodable { let points: Int }
        guard let monthStart = utcCalendar.dateInterval(of: .month, for: Date())?.start else { return 0 }

        let rows: [Row] = (try? await supabase
            .from("points_ledger")
            .select("points")
            .eq("user_id", value: userId)
            .eq("source", value: "habito")
            .gte("occurred_at", value: monthStart)
            .execute()
            .value) ?? []
        return rows.reduce(0) { $0 + $1.points }
    }

    /// Racha actual (dias consecutivos hasta ayer, UTC, con al menos un
    /// movimiento) — solo para mostrarla en la UI. Mismo criterio
    /// (ventana de 60 dias, limite UTC) que `award-habit-points` para
    /// que lo que ve el usuario coincida con lo que el servidor va a
    /// premiar.
    func currentStreakDays(userId: UUID) async -> Int {
        guard let windowStart = utcCalendar.date(byAdding: .day, value: -60, to: Date()) else { return 0 }

        struct Row: Decodable {
            let occurredAt: Date
            enum CodingKeys: String, CodingKey { case occurredAt = "occurred_at" }
        }
        let rows: [Row] = (try? await supabase
            .from("transactions")
            .select("occurred_at")
            .eq("user_id", value: userId)
            .gte("occurred_at", value: windowStart)
            .execute()
            .value) ?? []

        let days = Set(rows.map { utcCalendar.startOfDay(for: $0.occurredAt) })
        guard var cursor = utcCalendar.date(byAdding: .day, value: -1, to: utcCalendar.startOfDay(for: Date())) else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = utcCalendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

}
