import Foundation

/// Monto escrito a mano ("52,30", "$52.30", " 1,250.50 ") → Decimal.
/// Lo usan "Fue otro monto" en Hoy y la respuesta escrita de la
/// notificacion de un pago fijo.
enum RecurringAmountParser {
    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")
        if hasComma && hasDot {
            // El ultimo separador es el decimal: 1,250.50 o 1.250,50.
            if let comma = cleaned.lastIndex(of: ","), let dot = cleaned.lastIndex(of: "."), comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            // "52,30" es decimal; "1,250" (3 cifras despues) es miles.
            let parts = cleaned.split(separator: ",")
            if parts.count == 2, parts[1].count == 3 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            }
        }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." }),
              cleaned.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned), value > 0, value < 1_000_000
        else { return nil }
        return value
    }
}
