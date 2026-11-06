import Foundation
import Supabase

/// Logica de datos de movimientos compartida entre el "cuaderno del dia"
/// (ingreso ultra-rapido) y la pantalla de cuentas (formulario detallado),
/// para que ambos caminos escriban exactamente igual.
@MainActor
final class TransactionsRepository {
    static let shared = TransactionsRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    func fetchToday(userId: UUID) async throws -> [FinanceTransaction] {
        try await fetchDay(userId: userId, date: Date())
    }

    /// Igual que `fetchToday` pero para cualquier dia — lo usa el icono de
    /// calendario del dashboard para hojear dias anteriores.
    func fetchDay(userId: UUID, date: Date) async throws -> [FinanceTransaction] {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }

        return try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .gte("occurred_at", value: start)
            .lt("occurred_at", value: end)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Todos los movimientos del usuario, sin limite — para exportar a CSV.
    func fetchAll(userId: UUID) async throws -> [FinanceTransaction] {
        try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .order("occurred_at", ascending: false)
            .execute()
            .value
    }

    func fetchRecent(userId: UUID, limit: Int = 20) async throws -> [FinanceTransaction] {
        try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .order("occurred_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Busca movimientos por descripcion, o por etiqueta si el texto
    /// empieza con "#" (inspirado en "Buscar con Etiquetas").
    func search(userId: UUID, query: String) async throws -> [FinanceTransaction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("#") {
            let tag = String(trimmed.dropFirst())
            guard !tag.isEmpty else { return [] }
            return try await supabase
                .from("transactions")
                .select()
                .eq("user_id", value: userId)
                .contains("tags", value: [tag])
                .order("occurred_at", ascending: false)
                .execute()
                .value
        }

        return try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .ilike("description", pattern: "%\(trimmed)%")
            .order("occurred_at", ascending: false)
            .execute()
            .value
    }

    /// Neto (entradas - salidas) de cada uno de los `days` dias anteriores a
    /// hoy. Se usa para comparar el dia de hoy contra "como te ha ido" al
    /// cerrarlo (mejora #5, resumen al cerrar el dia).
    func fetchPastDailyNets(userId: UUID, days: Int) async throws -> [Decimal] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: today) else { return [] }

        let rows: [FinanceTransaction] = try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .gte("occurred_at", value: start)
            .lt("occurred_at", value: today)
            .execute()
            .value

        let grouped = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.occurredAt) }
        return grouped.values.map { dayRows in dayRows.reduce(Decimal(0)) { $0 + $1.amount } }
    }

    @discardableResult
    func add(_ new: NewTransaction) async throws -> FinanceTransaction {
        let created: FinanceTransaction = try await supabase
            .from("transactions")
            .insert(new)
            .select()
            .single()
            .execute()
            .value

        try await applyToAccountBalance(accountId: new.accountId, delta: new.amount)
        // Ya anoto algo hoy: el "¿Anotaste tus gastos de hoy?" de esta
        // noche ya no hace falta.
        NotificationManager.scheduleDailyLogReminders(loggedToday: true)
        return created
    }

    private struct TransactionEditFields: Encodable {
        let amount: Decimal
        let movementType: MovementType
        let category: String?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case movementType = "movement_type"
            case category
            case description
        }
    }

    /// Editar un movimiento ya guardado — hasta ahora, una vez anotado, no
    /// habia forma de corregir un typo en el monto o la categoria. Se deja
    /// la cuenta fija (cambiar de cuenta es borrar y anotar de nuevo) para
    /// no tener que mover saldo entre dos cuentas a la vez; el tipo si se
    /// puede cambiar (ej. "era ingreso, no gasto") porque el delta de saldo
    /// ya lo resuelve solo: se resta el monto viejo (con su signo) y se
    /// suma el nuevo.
    @discardableResult
    func update(
        _ transaction: FinanceTransaction,
        magnitude: Decimal,
        movementType: MovementType,
        category: String?,
        description: String?
    ) async throws -> FinanceTransaction {
        let newSignedAmount = movementType.signedAmount(from: magnitude)
        let delta = newSignedAmount - transaction.amount

        let updated: FinanceTransaction = try await supabase
            .from("transactions")
            .update(TransactionEditFields(
                amount: newSignedAmount,
                movementType: movementType,
                category: category,
                description: description
            ))
            .eq("id", value: transaction.id)
            .select()
            .single()
            .execute()
            .value

        if delta != 0 {
            try await applyToAccountBalance(accountId: transaction.accountId, delta: delta)
        }
        return updated
    }

    func delete(_ transaction: FinanceTransaction) async throws {
        try await supabase.from("transactions").delete().eq("id", value: transaction.id).execute()
        try await applyToAccountBalance(accountId: transaction.accountId, delta: -transaction.amount)
    }

    private struct IncrementBalanceParams: Encodable {
        let pAccountId: UUID
        let pDelta: Decimal

        enum CodingKeys: String, CodingKey {
            case pAccountId = "p_account_id"
            case pDelta = "p_delta"
        }
    }

    private func applyToAccountBalance(accountId: UUID, delta: Decimal) async throws {
        try await supabase
            .rpc("increment_account_balance", params: IncrementBalanceParams(pAccountId: accountId, pDelta: delta))
            .execute()
    }
}
