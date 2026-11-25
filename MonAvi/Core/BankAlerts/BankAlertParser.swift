import Foundation

/// Un movimiento leido de un aviso del banco (notificacion de la app del
/// banco o de Yappy, SMS o correo) que llega por una automatizacion de
/// Atajos (ver DetectBankMovementIntent).
struct ParsedBankMovement: Equatable {
    var amount: Decimal
    var isIncome: Bool
    /// Comercio (si es un gasto) o quien envio el dinero (si es ingreso).
    var counterpart: String?
    /// Ultimos 4 digitos de la tarjeta o cuenta, si el aviso los trae.
    var last4: String?
}

/// Lee el texto de un aviso del banco en el dispositivo (el texto no se
/// sube a ningun servidor). Reglas:
/// - nunca acepta codigos de seguridad (OTP, claves), transacciones
///   rechazadas ni promociones;
/// - el monto tiene que venir con su moneda (B/., $, USD) para no confundir
///   numeros de tarjeta o fechas;
/// - "te enviaron", "recibiste", "depósito"... es ingreso; "compra",
///   "consumo", "pagaste", "retiro"... es gasto. Si no es ninguno, no es
///   un movimiento.
/// El prototipo con los mismos casos esta en BankAlertParserTests.
enum BankAlertParser {
    /// Palabras que descartan el aviso completo.
    static let rejectWords = [
        "no compartas", "no lo compartas", "no la compartas", "codigo de verificacion", "codigo de seguridad",
        "codigo de acceso", "clave dinamica", "clave temporal", "otp", "token", "contrasena",
        "rechazad", "declinad", "no fue aprobad", "no aprobad", "fallid", "no exitos",
        "gana ", "promo", "oferta", "participa", "sorteo", "descuento de", "hasta $", "cashback de hasta",
    ]

    static let incomeWords = [
        "te enviaron", "te envio", "recibiste", "has recibido", "recibio", "te transfirio", "te transfirieron",
        "te pago", "te pagaron", "deposito", "depositaron", "acreditacion", "acreditad", "acreditamos", "abono",
        "abonaron", "transferencia recibida", "credito a tu cuenta", "credito a su cuenta", "reembolso",
        "devolucion", "ingreso de",
    ]

    static let expenseWords = [
        "compra", "consumo", "pagaste", "pago", "debito", "debitad", "retiro", "retiraste", "cargo",
        "enviaste", "transferiste", "transferencia", "transaccion", "avance de efectivo", "gastaste", "comercio",
    ]

    private static let number = #"(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let amountPrefix = regex(#"(?i)(?:b/\.?|usd|us\$|\$)\s?"# + number)
    private static let amountSuffix = regex("(?i)" + number + #"\s?(?:usd|dolares|dólares|balboas)"#)
    private static let otp = regex(#"(codigo|clave)[^.]{0,20}(es|:)\s*\d{4,8}"#)

    private static let stop = #"(?=\s+(?:el|la|con|por|fecha|tarjeta|a las|hoy|del|desde|mediante|via app|\d{1,2}[/-])\b|[,.;:!\n(]|\s-\s|$)"#
    private static let name = #"([A-ZÁÉÍÓÚÑ0-9][A-Za-zÁÉÍÓÚÑáéíóúñü0-9&'\-\. ]{1,40}?)"#
    private static let merchantField = regex(#"[Cc]omercio:?\s+"# + name + stop)
    private static let merchantEn = regex(#"(?:^|\s)en\s+"# + name + stop)
    private static let payee = regex(#"(?:[Pp]agaste|[Ee]nviaste|[Tt]ransferiste).{0,30}?\s(?:a)\s+"# + name + stop)
    private static let sender = regex(#"(?:^|\s)de\s+"# + name + stop)
    private static let last4Patterns = [
        #"(?i)terminad[ao]\s+en\s+(\d{4})\b"#,
        #"(?i)finalizad[ao]\s+en\s+(\d{4})\b"#,
        #"(?i)final\s+(\d{4})\b"#,
        #"[•*xX]{1,6}\s?(\d{4})\b"#,
        #"\.{3}\s?(\d{4})\b"#,
    ].map { regex($0) }

    static func parse(_ raw: String) -> ParsedBankMovement? {
        let text = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let folded = fold(text)
        guard !text.isEmpty else { return nil }
        if rejectWords.contains(where: { folded.contains($0) }) || firstMatch(otp, in: folded) != nil { return nil }

        guard let amountText = firstMatch(amountPrefix, in: text) ?? firstMatch(amountSuffix, in: text),
              let amount = parseNumber(amountText), amount > 0 else { return nil }

        let isIncome = incomeWords.contains(where: { folded.contains($0) })
        let isExpense = !isIncome && expenseWords.contains(where: { folded.contains($0) })
        guard isIncome || isExpense else { return nil }

        var counterpart: String?
        if isIncome {
            counterpart = cleanName(firstMatch(sender, in: text))
        } else {
            for pattern in [merchantField, payee, merchantEn] {
                if let found = cleanName(firstMatch(pattern, in: text)) {
                    counterpart = found
                    break
                }
            }
        }
        let last4 = last4Patterns.lazy.compactMap { firstMatch($0, in: text) }.first
        return ParsedBankMovement(amount: amount, isIncome: isIncome, counterpart: counterpart, last4: last4)
    }

    /// "1,250.00" → 1250; "800.000" → 800000 (miles); "12,40" → 12.40.
    static func parseNumber(_ raw: String) -> Decimal? {
        let lastDot = raw.lastIndex(of: "."), lastComma = raw.lastIndex(of: ",")
        var normalized: String
        if let dot = lastDot, let comma = lastComma {
            let decimalIndex = max(dot, comma)
            let integerPart = raw[..<decimalIndex].filter(\.isNumber)
            let fraction = raw[raw.index(after: decimalIndex)...]
            normalized = "\(integerPart).\(fraction)"
        } else if let separator = lastDot.map({ _ in Character(".") }) ?? lastComma.map({ _ in Character(",") }) {
            let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count <= 2 {
                normalized = "\(parts[0]).\(parts[1])"
            } else {
                normalized = parts.joined()
            }
        } else {
            normalized = raw
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
    }

    private static func cleanName(_ raw: String?) -> String? {
        guard var name = raw?.components(separatedBy: .whitespaces).filter({ !$0.isEmpty }).joined(separator: " ") else { return nil }
        while let last = name.last, last == "." || last == "-" || last == " " { name.removeLast() }
        guard name.count >= 2, !name.allSatisfy(\.isNumber) else { return nil }
        let firstWord = fold(name.split(separator: " ").first.map(String.init) ?? "")
        if ["tu", "su", "la", "el", "un", "una", "linea"].contains(firstWord) { return nil }
        if name == name.uppercased(), name.contains(where: \.isLetter) {
            name = name.lowercased().capitalized
        }
        return String(name.prefix(40))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patrones fijos: un error aqui es un bug de programacion.
        try! NSRegularExpression(pattern: pattern)
    }

    /// El primer grupo capturado de la primera coincidencia.
    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let groupRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
