import Foundation

/// Propuestas de "guardar como pago fijo" para Hoy (ver RecurringDetector).
@MainActor
final class RecurringSuggestionsModel: ObservableObject {
    @Published private(set) var suggestions: [RecurringDetector.Suggestion] = []

    private static func dismissedKey(_ userId: UUID) -> String { "monavi.recurringSuggestions.dismissed.\(userId.uuidString)" }

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
        suggestions = Array(
            RecurringDetector.suggestions(entries: entries, existingNames: existing.map(\.name), dismissed: dismissed).prefix(2)
        )
    }

    func dismiss(_ suggestion: RecurringDetector.Suggestion, userId: UUID) {
        var dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedKey(userId)) ?? []
        dismissed.append(suggestion.id)
        UserDefaults.standard.set(Array(dismissed.suffix(200)), forKey: Self.dismissedKey(userId))
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func accept(_ suggestion: RecurringDetector.Suggestion, userId: UUID, using recurring: RecurringTransactionsViewModel) async throws {
        try await recurring.add(
            NewRecurringTransaction(
                userId: userId,
                accountId: suggestion.accountId,
                name: suggestion.name,
                amount: suggestion.amount,
                movementType: .gasto,
                category: suggestion.category,
                dayOfMonth: suggestion.dayOfMonth
            )
        )
        suggestions.removeAll { $0.id == suggestion.id }
    }
}
