import Foundation

/// "Este gasto se repite cada mes": si la persona anoto el mismo gasto
/// (misma descripcion, monto parecido) una vez en dos meses seguidos y
/// todavia no es un pago fijo, MonAvi le propone guardarlo como fijo para
/// recordarselo. Logica pura (sin red) para poder probarla.
enum RecurringDetector {
    struct Entry: Equatable {
        var description: String
        /// Magnitud (positiva).
        var amount: Decimal
        var date: Date
        var accountId: UUID
        var category: String?
    }

    struct Suggestion: Identifiable, Equatable {
        /// Descripcion normalizada: sirve para "No, gracias" (no volver a
        /// proponerlo).
        let id: String
        let name: String
        /// El ultimo monto pagado.
        let amount: Decimal
        let dayOfMonth: Int
        let accountId: UUID
        let category: String?
        /// Los dos meses en que aparecio, ej. "octubre y noviembre".
        let monthsText: String
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// - entries: gastos de los ultimos ~3 meses.
    /// - existingNames: nombres de los pagos fijos que ya tiene.
    /// - dismissed: claves que ya rechazo.
    static func suggestions(
        entries: [Entry],
        existingNames: [String],
        dismissed: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Suggestion] {
        let existing = existingNames.map(normalize).filter { !$0.isEmpty }
        let currentMonth = monthIndex(now, calendar)

        let groups = Dictionary(grouping: entries.filter { normalize($0.description).count >= 3 }) { normalize($0.description) }
        var result: [Suggestion] = []

        for (key, items) in groups {
            guard !dismissed.contains(key) else { continue }
            if existing.contains(where: { $0 == key || $0.contains(key) || key.contains($0) }) { continue }

            let byMonth = Dictionary(grouping: items) { monthIndex($0.date, calendar) }
            // Algo que se compra varias veces al mes (super, gasolina) no es
            // un pago fijo.
            guard byMonth.values.allSatisfy({ $0.count == 1 }) else { continue }

            // Dos meses seguidos dentro de los ultimos 3 (este incluido).
            let months = byMonth.keys.filter { $0 >= currentMonth - 2 && $0 <= currentMonth }.sorted()
            guard let pair = zip(months, months.dropFirst()).last(where: { $1 - $0 == 1 }) else { continue }
            guard let first = byMonth[pair.0]?.first, let second = byMonth[pair.1]?.first else { continue }

            // Montos parecidos (la luz cambia un poco; un 30% como maximo).
            let low = min(first.amount, second.amount)
            let high = max(first.amount, second.amount)
            guard high > 0, low / high >= Decimal(string: "0.7")! else { continue }

            result.append(
                Suggestion(
                    id: key,
                    name: displayName(second.description),
                    amount: second.amount,
                    dayOfMonth: calendar.component(.day, from: second.date),
                    accountId: second.accountId,
                    category: second.category ?? first.category,
                    monthsText: "\(monthName(first.date, calendar)) y \(monthName(second.date, calendar))"
                )
            )
        }
        return result.sorted { $0.amount > $1.amount }
    }

    /// "luz" -> "Luz" (si la escribio todo en minuscula).
    static func displayName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == trimmed.lowercased(), let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    private static func monthIndex(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
    }

    private static func monthName(_ date: Date, _ calendar: Calendar) -> String {
        let names = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                     "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        return names[(calendar.component(.month, from: date) - 1 + 12) % 12]
    }
}
