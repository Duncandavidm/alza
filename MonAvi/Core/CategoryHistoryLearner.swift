import Foundation

/// Aprende del historial del usuario (la mejor señal): si siempre anota
/// "Arriendo" como Vivienda, o "Chino de la esquina" con su categoria
/// propia "Comida rápida", la proxima vez se sugiere lo mismo. Puro y sin
/// red: se arma una vez con los ultimos movimientos y se consulta mientras
/// escribe.
///
/// Busca primero la descripcion normalizada completa (sin tildes,
/// mayusculas ni signos) y si no, la primera palabra significativa (se
/// saltan "pago", "de", "el", "compra"...). Gana la categoria mas usada;
/// ante un empate, la mas reciente (las entradas vienen de la mas nueva a
/// la mas vieja, como las da `fetchRecent`).
struct CategoryHistoryLearner {
    struct Entry: Hashable {
        let description: String
        /// Lo guardado en `transactions.category` (fija o propia).
        let category: String
        let isInflow: Bool
    }

    /// Palabras que no dicen nada del "que fue".
    static let stopwords: Set<String> = [
        "de", "del", "la", "el", "los", "las", "lo", "en", "para", "por", "un", "una", "unos",
        "unas", "mi", "mis", "su", "sus", "al", "a", "y", "con", "sin", "que", "pago", "pague",
        "compra", "compre", "gasto", "gaste", "abono", "cuota", "me", "le", "se", "hoy", "ayer",
    ]

    private struct Tally {
        var counts: [String: Int] = [:]
        /// Indice de la entrada mas reciente con esa categoria (menor = mas nueva).
        var newest: [String: Int] = [:]

        mutating func add(_ category: String, index: Int) {
            counts[category, default: 0] += 1
            if newest[category] == nil { newest[category] = index }
        }

        var winner: String? {
            counts.max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                // Empate: gana la mas reciente (indice menor).
                return (newest[lhs.key] ?? .max) > (newest[rhs.key] ?? .max)
            }?.key
        }
    }

    private struct Key: Hashable {
        let text: String
        let isInflow: Bool
    }

    private var byDescription: [Key: Tally] = [:]
    private var byFirstWord: [Key: Tally] = [:]

    init(entries: [Entry]) {
        for (index, entry) in entries.enumerated() {
            let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty else { continue }
            let words = CategoryKeywordGuesser.normalizedWords(entry.description)
            guard !words.isEmpty else { continue }

            byDescription[Key(text: words.joined(separator: " "), isInflow: entry.isInflow), default: Tally()]
                .add(category, index: index)
            if let first = Self.firstSignificantWord(in: words) {
                byFirstWord[Key(text: first, isInflow: entry.isInflow), default: Tally()]
                    .add(category, index: index)
            }
        }
    }

    /// Desde movimientos ya guardados (los que no tienen descripcion o
    /// categoria se ignoran).
    init(transactions: [FinanceTransaction]) {
        self.init(entries: transactions.compactMap { transaction in
            guard let description = transaction.description,
                  let category = transaction.category
            else { return nil }
            return Entry(
                description: description,
                category: category,
                isInflow: transaction.movementType.isInflow
            )
        })
    }

    var isEmpty: Bool { byDescription.isEmpty }

    /// La categoria (texto guardado) que el usuario suele usar para `text`,
    /// o nil si no hay historial parecido.
    func category(for text: String, isInflow: Bool) -> String? {
        let words = CategoryKeywordGuesser.normalizedWords(text)
        guard !words.isEmpty else { return nil }

        if let exact = byDescription[Key(text: words.joined(separator: " "), isInflow: isInflow)]?.winner {
            return exact
        }
        guard let first = Self.firstSignificantWord(in: words) else { return nil }
        return byFirstWord[Key(text: first, isInflow: isInflow)]?.winner
    }

    /// La primera palabra de 3+ letras que no es de relleno ni un numero.
    static func firstSignificantWord(in words: [String]) -> String? {
        words.first { word in
            word.count >= 3
                && !stopwords.contains(word)
                && !word.allSatisfy(\.isNumber)
        }
    }
}
