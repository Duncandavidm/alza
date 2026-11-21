import Foundation

/// Gastos que se repiten (ver RecurringDetector): la tarjeta en Hoy y la
/// notificacion "Pagaste Luz el 12 de octubre y el 13 de noviembre. ¿Este
/// mes ya lo pagaste?" usan esta misma logica para guardar o descartar.
@MainActor
final class RecurringSuggestionsModel: ObservableObject {
    @Published private(set) var suggestions: [RecurringDetector.Suggestion] = []

    nonisolated static func dismissedKey(_ userId: UUID) -> String { "monavi.recurringSuggestions.dismissed.\(userId.uuidString)" }

    func refresh(userId: UUID, existing: [RecurringTransaction]) async {
        guard let since = Calendar.current.date(byAdding: .day, value: -95, to: Date()),
              let rows = try? await TransactionsRepository.shared.fetchSince(userId: userId, date: since)
        else { return }
        let entries = rows
            .filter { $0.movementType == .gasto }
            .compactMap { row -> RecurringDetector.Entry? in
                guard let description = row.description, !description.isEmpty else { return nil }
                return RecurringDetector.Entry(
                    description: description,
                    amount: abs(row.amount),
                    date: row.occurredAt,
                    accountId: row.accountId,
                    category: row.category
                )
            }
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey(userId)) ?? [])
        let found = RecurringDetector.suggestions(entries: entries, existingNames: existing.map(\.name), dismissed: dismissed)
        suggestions = Array(found.prefix(2))
        NotificationManager.scheduleSuggestedRecurring(suggestions)
    }

    /// "No es un gasto fijo": no se vuelve a proponer.
    nonisolated static func markDismissed(key: String, userId: UUID) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey(userId)) ?? []
        guard !dismissed.contains(key) else { return }
        dismissed.append(key)
        UserDefaults.standard.set(Array(dismissed.suffix(200)), forKey: dismissedKey(userId))
    }

    func dismiss(_ suggestion: RecurringDetector.Suggestion, userId: UUID) {
        Self.markDismissed(key: suggestion.id, userId: userId)
        suggestions.removeAll { $0.id == suggestion.id }
        NotificationManager.scheduleSuggestedRecurring(suggestions)
    }

    /// Lo guarda como pago fijo (para recordarlo cada mes) y, si
    /// `paidAmount` no es nil, anota el pago de este mes con ese monto.
    func accept(
        _ suggestion: RecurringDetector.Suggestion,
        userId: UUID,
        paidAmount: Decimal?,
        using recurring: RecurringTransactionsViewModel
    ) async throws {
        try await Self.save(
            name: suggestion.name,
            amount: paidAmount ?? suggestion.amount,
            dayOfMonth: suggestion.dayOfMonth,
            accountId: suggestion.accountId,
            category: suggestion.category,
            userId: userId,
            logPayment: paidAmount != nil
        )
        suggestions.removeAll { $0.id == suggestion.id }
        NotificationManager.scheduleSuggestedRecurring(suggestions)
        await recurring.refresh(userId: userId)
    }

    /// Sin pantalla: la usan la tarjeta de Hoy y los botones de la
    /// notificacion (que corren en segundo plano).
    static func save(
        name: String,
        amount: Decimal,
        dayOfMonth: Int,
        accountId: UUID,
        category: String?,
        userId: UUID,
        logPayment: Bool
    ) async throws {
        let created: RecurringTransaction = try await SupabaseManager.shared.client
            .from("recurring_transactions")
            .insert(
                NewRecurringTransaction(
                    userId: userId,
                    accountId: accountId,
                    name: name,
                    amount: amount,
                    movementType: .gasto,
                    category: category,
                    dayOfMonth: min(max(dayOfMonth, 1), 31)
                )
            )
            .select()
            .single()
            .execute()
            .value
        if logPayment {
            try await RecurringTransactionsViewModel.logPayment(for: created, userId: userId, amount: amount)
        }
    }
}
