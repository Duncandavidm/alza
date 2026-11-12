import Foundation

/// Interpreta en el dispositivo las frases de voz simples ("gasté 12 dólares
/// en almuerzo", "me pagaron 500 de salario") para no gastar una llamada a
/// la IA (parse-voice-transaction tiene cupo mensual) en algo tan directo.
///
/// Es conservador a proposito: solo devuelve un resultado cuando esta
/// seguro. Ante cualquier duda (dos montos, transferencias, deudas,
/// proveedores, inversiones, otras monedas, frases largas...) devuelve nil
/// y se usa la IA como siempre. Una respuesta equivocada es peor que una
/// llamada de mas.
enum SimpleVoiceParser {

    // MARK: - Vocabulario (todo en minusculas y sin tildes)

    /// Verbos/sustantivos de gasto.
    private static let spendWords: Set<String> = [
        "gaste", "gastamos", "gasto", "pague", "pagamos", "compre", "compramos",
    ]

    /// Verbos de ingreso que se entienden solos.
    private static let incomeWords: Set<String> = [
        "cobre", "cobramos", "recibi", "recibimos", "gane", "ganamos",
        "vendi", "vendimos", "ingreso",
    ]

    /// Verbos de ingreso que solo cuentan con "me" delante ("me pagaron",
    /// "me depositaron"). Sin "me" son ambiguos ("pagaron la luz") → nil.
    private static let incomeWordsNeedingMe: Set<String> = [
        "pagaron", "pago", "depositaron",
    ]

    /// Palabras que indican algo que no es un gasto/ingreso simple
    /// (transferencias, deudas, proveedores, inversiones, ahorro, otras
    /// monedas, centavos, porcentajes, preguntas, negaciones...).
    private static let blockedWords: Set<String> = [
        "pase", "pasamos", "pasaron", "mande", "mandaron", "envie", "enviaron", "yappy",
        "debo", "debe", "debemos", "deben", "deuda", "deudas", "fiado", "fie",
        "cuota", "cuotas", "tarjeta", "credito",
        "proveedor", "proveedores", "inversion", "inversiones",
        "retire", "retiro", "cajero", "factura", "facturas",
        "deposite", "deposito", "depositar", "vuelto", "cambio",
        "no", "nada", "cada", "mitad", "medio", "porciento", "cuanto",
        "cent", "real", "reales",
        "millon", "millones", "k",
    ]

    /// Prefijos bloqueados (cubren conjugaciones y derivados).
    private static let blockedPrefixes: [String] = [
        "transfer", "transfir", "prest", "abon", "invert", "invirt", "ahorr",
        "devol", "devuel", "reembols", "centavo", "euro", "peso", "colon",
    ]

    private static let currencyWords: Set<String> = [
        "$", "dolar", "dolares", "balboa", "balboas", "usd", "us", "palos",
    ]

    private static let prepositions: Set<String> = ["en", "de", "del", "por", "para", "a", "al", "con"]
    private static let articles: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "mi", "mis", "lo",
    ]
    private static let connectors: Set<String> = ["y", "que", "o"]
    private static let timeWords: Set<String> = [
        "hoy", "ayer", "anoche", "ahorita", "ahora", "antier", "anteayer", "recien",
    ]

    /// Conceptos comunes con su categoria. Ademas, son los unicos que se
    /// aceptan sin verbo ("almuerzo 8 dólares").
    private static let conceptCategories: [String: TransactionCategory] = [
        "almuerzo": .food, "desayuno": .food, "cena": .food, "comida": .food,
        "cafe": .food, "merienda": .food,
        "gasolina": .transport, "taxi": .transport, "uber": .transport, "pasaje": .transport,
        "bus": .transport, "metro": .transport, "peaje": .transport,
        "estacionamiento": .transport, "parking": .transport,
        "super": .groceries, "supermercado": .groceries,
        "luz": .utilities, "agua": .utilities, "internet": .utilities, "electricidad": .utilities,
        "farmacia": .health, "medicina": .health, "medicinas": .health,
        "alquiler": .housing,
        "cine": .entertainment,
    ]

    // MARK: - Numeros en palabras

    private enum NumberWord {
        case unit(Int)        // 1-9 ("uno"/"un" solo despues de "y")
        case tens(Int)        // 30-90, admiten "y <unidad>"
        case complete(Int)    // 10-29: no admiten "y"
        case hundreds(Int)    // 100-900
        case thousand
    }

    private static let numberWords: [String: NumberWord] = [
        "uno": .unit(1), "un": .unit(1), "dos": .unit(2), "tres": .unit(3), "cuatro": .unit(4),
        "cinco": .unit(5), "seis": .unit(6), "siete": .unit(7), "ocho": .unit(8), "nueve": .unit(9),
        "diez": .complete(10), "once": .complete(11), "doce": .complete(12), "trece": .complete(13),
        "catorce": .complete(14), "quince": .complete(15), "dieciseis": .complete(16),
        "diecisiete": .complete(17), "dieciocho": .complete(18), "diecinueve": .complete(19),
        "veinte": .complete(20), "veintiuno": .complete(21), "veintiun": .complete(21),
        "veintidos": .complete(22), "veintitres": .complete(23), "veinticuatro": .complete(24),
        "veinticinco": .complete(25), "veintiseis": .complete(26), "veintisiete": .complete(27),
        "veintiocho": .complete(28), "veintinueve": .complete(29),
        "treinta": .tens(30), "cuarenta": .tens(40), "cincuenta": .tens(50), "sesenta": .tens(60),
        "setenta": .tens(70), "ochenta": .tens(80), "noventa": .tens(90),
        "cien": .hundreds(100), "ciento": .hundreds(100),
        "doscientos": .hundreds(200), "doscientas": .hundreds(200),
        "trescientos": .hundreds(300), "trescientas": .hundreds(300),
        "cuatrocientos": .hundreds(400), "cuatrocientas": .hundreds(400),
        "quinientos": .hundreds(500), "quinientas": .hundreds(500),
        "seiscientos": .hundreds(600), "seiscientas": .hundreds(600),
        "setecientos": .hundreds(700), "setecientas": .hundreds(700),
        "ochocientos": .hundreds(800), "ochocientas": .hundreds(800),
        "novecientos": .hundreds(900), "novecientas": .hundreds(900),
        "mil": .thousand,
    ]

    private static let maxTokens = 14
    private static let maxDescriptionWords = 6
    private static let maxAmount: Double = 1_000_000

    // MARK: - Parse

    private struct Token {
        let original: String
        let folded: String
    }

    static func parse(_ transcript: String) -> ParsedVoiceTransaction? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("?"), !trimmed.contains("¿"), !trimmed.contains("%") else {
            return nil
        }

        let tokens = tokenize(trimmed)
        guard !tokens.isEmpty, tokens.count <= maxTokens else { return nil }

        guard !tokens.contains(where: { isBlocked($0.folded) }) else { return nil }

        // 1) Exactamente un monto (cifras o palabras).
        var removed = Array(repeating: false, count: tokens.count)
        var amounts: [Double] = []
        var index = 0
        while index < tokens.count {
            let folded = tokens[index].folded
            if folded.contains(where: \.isNumber) {
                guard let value = parseNumeric(folded) else { return nil }
                // "5 mil", "20 cinco": cifras pegadas a palabras numericas → duda.
                if index + 1 < tokens.count, numberWords[tokens[index + 1].folded] != nil {
                    return nil
                }
                amounts.append(value)
                removed[index] = true
                index += 1
            } else if startsNumberRun(folded) {
                guard let run = parseNumberRun(tokens.map(\.folded), from: index) else {
                    return nil
                }
                amounts.append(run.value)
                for offset in 0..<run.length { removed[index + offset] = true }
                index += run.length
            } else {
                index += 1
            }
        }
        guard amounts.count == 1, let amount = amounts.first, amount > 0, amount < maxAmount else {
            return nil
        }

        // 2) Tipo de movimiento por el verbo.
        var hasSpend = false
        var hasIncome = false
        for (i, token) in tokens.enumerated() where !removed[i] {
            let folded = token.folded
            let previous = i > 0 ? tokens[i - 1].folded : ""
            if spendWords.contains(folded) {
                hasSpend = true
                removed[i] = true
            } else if incomeWords.contains(folded) {
                hasIncome = true
                removed[i] = true
            } else if incomeWordsNeedingMe.contains(folded) {
                guard previous == "me" else { return nil }
                hasIncome = true
                removed[i] = true
            }
        }
        if hasSpend && hasIncome { return nil }

        // Pronombre "me" ("me gasté", "me pagaron"), moneda y tiempo no son
        // parte del concepto.
        for (i, token) in tokens.enumerated() where !removed[i] {
            let folded = token.folded
            let next = i + 1 < tokens.count ? tokens[i + 1].folded : ""
            if folded == "me" || currencyWords.contains(folded) || timeWords.contains(folded) {
                removed[i] = true
            } else if folded == "esta", ["manana", "tarde", "noche"].contains(next) {
                removed[i] = true
                removed[i + 1] = true
            }
        }

        // 3) Concepto: un solo tramo de palabras entre lo quitado.
        var segments: [[Token]] = []
        var current: [Token] = []
        for (i, token) in tokens.enumerated() {
            if removed[i] {
                if !current.isEmpty { segments.append(current) }
                current = []
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty { segments.append(current) }

        let concepts = segments.map(stripFillers).filter { !$0.isEmpty }
        guard concepts.count <= 1 else { return nil }
        let concept = concepts.first ?? []
        guard concept.count <= maxDescriptionWords else { return nil }

        let movementType: MovementType
        if hasIncome {
            movementType = .ingreso
        } else if hasSpend {
            movementType = .gasto
        } else {
            // Sin verbo: solo "<concepto conocido> <monto>" ("almuerzo 8 dólares").
            guard concept.count == 1, conceptCategories[concept[0].folded] != nil else { return nil }
            movementType = .gasto
        }

        let description: String
        if concept.isEmpty {
            // "cobré 200", "me depositaron 1000": un ingreso sin concepto
            // igual es claro. Un gasto sin concepto no.
            guard movementType == .ingreso else { return nil }
            description = "Ingreso"
        } else {
            description = capitalizedFirst(concept.map(\.original).joined(separator: " "))
        }

        let category: String?
        if movementType == .ingreso {
            category = TransactionCategory.income.rawValue
        } else if let known = concept.lazy.compactMap({ conceptCategories[$0.folded] }).first {
            category = known.rawValue
        } else {
            category = MerchantCategoryGuesser.category(for: description)?.rawValue
        }

        return ParsedVoiceTransaction(
            amount: amount,
            description: description,
            movementType: movementType,
            category: category
        ).normalizedForQuickAdd()
    }

    // MARK: - Helpers

    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!¡\"'()«»“”‘’…-")

    private static func tokenize(_ text: String) -> [Token] {
        let spaced = text.replacingOccurrences(of: "$", with: " $ ")
        return spaced
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
            .map { Token(original: $0, folded: fold($0)) }
    }

    static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func isBlocked(_ folded: String) -> Bool {
        if blockedWords.contains(folded) { return true }
        return blockedPrefixes.contains { folded.hasPrefix($0) }
    }

    /// Quita preposiciones, articulos y conectores sueltos al inicio y al
    /// final de un tramo ("en el super" → "super", "café por" → "café").
    private static func stripFillers(_ segment: [Token]) -> [Token] {
        let isFiller: (Token) -> Bool = {
            prepositions.contains($0.folded) || articles.contains($0.folded) || connectors.contains($0.folded)
        }
        var result = segment
        while let first = result.first, isFiller(first) { result.removeFirst() }
        while let last = result.last, isFiller(last) { result.removeLast() }
        return result
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "12", "45.50", "45,50", "1,000", "1.000", "1,250.75". Cualquier otra
    /// forma (horas, "5k", "1ro"...) → nil.
    static func parseNumeric(_ token: String) -> Double? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else {
            return nil
        }
        var groups: [String] = []
        var separators: [Character] = []
        var current = ""
        for char in token {
            if char == "." || char == "," {
                groups.append(current)
                separators.append(char)
                current = ""
            } else {
                current.append(char)
            }
        }
        groups.append(current)
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }

        if separators.isEmpty {
            guard token.count <= 7 else { return nil }
            return Double(token)
        }

        let first = groups[0]
        let last = groups[groups.count - 1]
        let middle = groups.dropFirst().dropLast()

        if separators.count == 1 {
            if last.count == 3, (1...3).contains(first.count) {
                return Double(first + last)                // miles: 1,000 / 1.000
            }
            if (1...2).contains(last.count), first.count <= 7 {
                return Double(first + "." + last)          // decimales: 45.50 / 45,50
            }
            return nil
        }

        guard (1...3).contains(first.count), middle.allSatisfy({ $0.count == 3 }) else { return nil }
        let thousandSeparator = separators[0]
        let earlierSame = separators.dropLast().allSatisfy { $0 == thousandSeparator }
        guard earlierSame else { return nil }

        if separators.last == thousandSeparator {
            guard last.count == 3 else { return nil }      // 1,000,000
            return Double(groups.joined())
        }
        guard (1...2).contains(last.count) else { return nil } // 1,250.75
        return Double(groups.dropLast().joined() + "." + last)
    }

    private static func startsNumberRun(_ folded: String) -> Bool {
        guard let word = numberWords[folded] else { return false }
        if case .unit(1) = word { return false }           // "un cliente", "una pizza"
        return true
    }

    /// Lee un numero en palabras desde `start` ("doscientos cincuenta",
    /// "treinta y cinco", "mil quinientos"). Devuelve el valor y cuantas
    /// palabras ocupo, o nil si la forma no es valida (y entonces no se
    /// adivina).
    private static func parseNumberRun(_ words: [String], from start: Int) -> (value: Double, length: Int)? {
        // Rango del numero: 4 = inicio de grupo, 3 = centenas, 2 = decenas, 1 = unidades.
        var total = 0
        var group = 0
        var lastSlot = 4
        var previousWasTens = false
        var previousWord = ""
        var index = start

        while index < words.count {
            let word = words[index]
            if word == "y" {
                let next = index + 1 < words.count ? words[index + 1] : ""
                guard let nextWord = numberWords[next], case .unit = nextWord else { break }
                guard previousWasTens else { return nil }
                previousWord = word
                index += 1
                continue
            }
            guard let numberWord = numberWords[word] else { break }

            switch numberWord {
            case .unit(let value):
                if value == 1 && previousWord != "y" { return nil }
                if lastSlot == 2 && previousWord != "y" { return nil }   // "treinta cinco"
                guard lastSlot > 1 else { return nil }
                group += value
                lastSlot = 1
                previousWasTens = false
            case .tens(let value):
                guard lastSlot > 2 else { return nil }
                group += value
                lastSlot = 2
                previousWasTens = true
            case .complete(let value):
                guard lastSlot > 2 else { return nil }
                group += value
                lastSlot = 2
                previousWasTens = false
            case .hundreds(let value):
                guard lastSlot > 3 else { return nil }
                let next = index + 1 < words.count ? words[index + 1] : ""
                let nextIsNumber = numberWords[next] != nil
                if word == "cien", nextIsNumber, next != "mil" {
                    return nil                             // "cien" va solo o antes de "mil"
                }
                if word == "ciento", !nextIsNumber || next == "mil" {
                    return nil                             // "ciento" siempre lleva algo despues
                }
                group += value
                lastSlot = 3
                previousWasTens = false
            case .thousand:
                guard total == 0 else { return nil }
                total = (group == 0 ? 1 : group) * 1000
                group = 0
                lastSlot = 4
                previousWasTens = false
            }
            previousWord = word
            index += 1
        }

        let length = index - start
        guard length > 0 else { return nil }
        let value = total + group
        guard value > 0 else { return nil }
        return (value: Double(value), length: length)
    }
}
