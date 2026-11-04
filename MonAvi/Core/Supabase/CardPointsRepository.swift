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

    // MARK: - Ahorro verificado (Fase 3)

    func fetchActiveBankPartners() async throws -> [BankPartner] {
        try await supabase
            .from("bank_partners")
            .select()
            .eq("status", value: BankPartnerStatus.active.rawValue)
            .order("name", ascending: true)
            .execute()
            .value
    }

    /// Todos los bancos (activos o pausados) — para mostrar el nombre
    /// de un banco con el que el usuario ya esta inscrito, aunque se
    /// haya pausado despues. Para elegir un banco NUEVO se usa
    /// `fetchActiveBankPartners`.
    func fetchAllBankPartners() async throws -> [BankPartner] {
        try await supabase
            .from("bank_partners")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
    }

    /// Inscripciones activas del usuario — normalmente una sola, pero el
    /// esquema permite mas de un banco patrocinador a la vez.
    func fetchActiveSavingsEnrollments(userId: UUID) async throws -> [SponsoredSavingsEnrollment] {
        try await supabase
            .from("sponsored_savings_enrollments")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: SavingsEnrollmentStatus.active.rawValue)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func enroll(_ new: NewSponsoredSavingsEnrollment) async throws -> SponsoredSavingsEnrollment {
        try await supabase
            .from("sponsored_savings_enrollments")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
    }

    /// Revocar solo cambia el estado — nunca borra las metas o puntos ya
    /// otorgados. El reporte del banco deja de procesarse para esta
    /// inscripcion (ver reconcile-savings-reports, filtra por status
    /// 'active').
    func revokeConsent(_ enrollment: SponsoredSavingsEnrollment) async throws {
        try await supabase
            .from("sponsored_savings_enrollments")
            .update(SponsoredSavingsEnrollmentRevoke(status: .revoked, consentRevokedAt: Date()))
            .eq("id", value: enrollment.id)
            .execute()
    }

    func fetchSavingsGoals(enrollmentId: UUID) async throws -> [SponsoredSavingsGoal] {
        try await supabase
            .from("sponsored_savings_goals")
            .select()
            .eq("enrollment_id", value: enrollmentId)
            .order("period_month", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func createSavingsGoal(_ new: NewSponsoredSavingsGoal) async throws -> SponsoredSavingsGoal {
        try await supabase
            .from("sponsored_savings_goals")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
    }

    /// Puntos de ahorro pendientes vs confirmados — a diferencia de
    /// `fetchBalance` (que suma TODAS las fuentes), esto filtra solo
    /// source='ahorro' para mostrarlo por separado en "Mis metas".
    func savingsPointsBreakdown(userId: UUID) async -> (pending: Int, confirmed: Int) {
        struct Row: Decodable {
            let points: Int
            let status: String
        }
        let rows: [Row] = (try? await supabase
            .from("points_ledger")
            .select("points, status")
            .eq("user_id", value: userId)
            .eq("source", value: "ahorro")
            .execute()
            .value) ?? []

        var pending = 0
        var confirmed = 0
        for row in rows {
            switch row.status {
            case "pendiente": pending += row.points
            case "confirmado": confirmed += row.points
            default: break
            }
        }
        return (pending: pending, confirmed: confirmed)
    }
}
