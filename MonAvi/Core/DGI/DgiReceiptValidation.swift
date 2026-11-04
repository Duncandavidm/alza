import Foundation

/// Reglas de frescura de una factura escaneada — separadas de
/// `CufeParser` porque dependen de "hoy" (no son parseo puro), pero
/// siguen siendo logica sin red/base de datos, facil de probar con una
/// fecha fija inyectada.
enum DgiReceiptValidation {
    /// Cuantos dias hacia atras se acepta una factura desde su fecha de
    /// emision (la que trae el CUFE), antes de rechazarla por vieja.
    static let maxDaysInPast = 3

    enum FreshnessResult: Equatable {
        case ok
        case future
        case tooOld
        case invalidDate
    }

    /// `fechaISO` = "yyyy-MM-dd" (viene de `CufeFields.fechaISO`).
    static func checkFreshness(fechaISO: String, now: Date = Date(), calendar: Calendar = .current) -> FreshnessResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")

        guard let fecha = formatter.date(from: fechaISO) else { return .invalidDate }

        let today = calendar.startOfDay(for: now)
        let fechaDay = calendar.startOfDay(for: fecha)

        guard let days = calendar.dateComponents([.day], from: fechaDay, to: today).day else {
            return .invalidDate
        }

        if days < 0 { return .future }
        if days > maxDaysInPast { return .tooOld }
        return .ok
    }
}
