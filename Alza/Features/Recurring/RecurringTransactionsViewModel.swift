import Foundation
import Supabase

@MainActor
final class RecurringTransactionsViewModel: ObservableObject {
    @Published private(set) var items: [RecurringTransaction] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private var dismissedTodayIds: Set<UUID> = []

    private let supabase = SupabaseManager.shared.client

    var dueToday: [RecurringTransaction] {
        items.filter { $0.isDueToday() && !dismissedTodayIds.contains($0.id) }
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await supabase
                .from("recurring_transactions")
                .select()
                .eq("user_id", value: userId)
                .order("day_of_month", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudieron cargar tus recurrentes: \(error.localizedDescription)"
        }
    }

    func add(_ new: NewRecurringTransaction) async throws {
        let created: RecurringTransaction = try await supabase
            .from("recurring_transactions")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        items.append(created)
    }

    func delete(_ item: RecurringTransaction) async throws {
        try await supabase.from("recurring_transactions").delete().eq("id", value: item.id).execute()
        items.removeAll { $0.id == item.id }
    }

    /// Registra el pago de hoy: crea el movimiento real y marca la
    /// recurrente como pagada este mes.
    func confirmPayment(for item: RecurringTransaction, userId: UUID) async throws {
        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: item.accountId,
                amount: item.movementType.signedAmount(from: item.amount),
                movementType: item.movementType,
                category: item.category,
                description: item.name,
                occurredAt: Date()
            )
        )

        let today = Date()
        try await supabase
            .from("recurring_transactions")
            .update(["last_logged_on": ISO8601DateFormatter().string(from: today)])
            .eq("id", value: item.id)
            .execute()

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].lastLoggedOn = today
        }
    }

    /// El usuario dice "todavia no", asi que no se registra nada, solo
    /// dejamos de recordarselo por hoy (no se guarda en la base, es un
    /// dismiss local nada mas — vuelve a aparecer al reabrir la app).
    func dismissReminder(for item: RecurringTransaction) {
        dismissedTodayIds.insert(item.id)
    }
}
