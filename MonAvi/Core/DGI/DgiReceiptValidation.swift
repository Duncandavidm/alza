import Foundation

/// Reglas de frescura de una factura escaneada — separadas de
/// `CufeParser` porque dependen de "hoy" (no son parseo puro), pero
/// siguen siendo logica sin red/base de datos, facil de probar con una
/// fecha fija inyectada.
///
/// Regla (1.0.6):
/// - Factura del mes en curso: siempre se registra. El cashback depende de
///   cuantos dias pasaron desde la fecha de la factura:
///   0 a 3 dias = completo, 4 a 7 dias = la mitad, 8 o mas = un cuarto.
/// - Factura del mes anterior: solo los 3 primeros dias del mes. Se
///   registra el gasto (con la fecha de la factura, en su mes) pero sin
///   cashback.
/// - Cualquier otra mas vieja: no se registra.
///
/// El servidor (verify-dgi-receipt) aplica la misma regla al acreditar.
enum DgiReceiptValidation {
    /// Hasta cuantos dias se gana el cashback completo.
    static let fullCashbackDays = 3
    /// Hasta cuantos dias se gana la mitad.
    static let halfCashbackDays = 7
    /// Los primeros N dias del mes todavia se aceptan facturas del mes
    /// anterior (sin cashback).
    static let previousMonthGraceDays = 3

    enum CashbackTier: Equatable {
        case full
        case half
        case quarter
        /// Factura del mes anterior: se registra el gasto, sin cashback.
        case none

        var multiplier: Double {
            switch self {
            case .full: return 1
            case .half: return 0.5
            case .quarter: return 0.25
            case .none: return 0
            }
        }
    }

    enum FreshnessResult: Equatable {
        case ok(CashbackTier)
        case future
        case tooOld
        case invalidDate
    }

    /// `fechaISO` = "yyyy-MM-dd" (viene de `CufeFields.fechaISO`).
    static func checkFreshness(fechaISO: String, now: Date = Date(), calendar: Calendar = .current) -> FreshnessResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        // La fecha de la factura es un dia calendario de Panama: se lee en la
        // misma zona horaria del calendario con el que se compara. Antes se
        // leia en UTC y, en Panama (UTC-5), caia en el dia anterior.
        formatter.timeZone = calendar.timeZone

        guard let fecha = formatter.date(from: fechaISO) else { return .invalidDate }

        let today = calendar.startOfDay(for: now)
        let fechaDay = calendar.startOfDay(for: fecha)

        guard let days = calendar.dateComponents([.day], from: fechaDay, to: today).day else {
            return .invalidDate
        }
        if days < 0 { return .future }

        let todayParts = calendar.dateComponents([.year, .month, .day], from: today)
        let fechaParts = calendar.dateComponents([.year, .month], from: fechaDay)
        guard let todayYear = todayParts.year, let todayMonth = todayParts.month, let todayDay = todayParts.day,
              let fechaYear = fechaParts.year, let fechaMonth = fechaParts.month else {
            return .invalidDate
        }

        // Mismo mes: se acepta siempre; el cashback baja con los dias.
        if fechaYear == todayYear && fechaMonth == todayMonth {
            if days <= fullCashbackDays { return .ok(.full) }
            if days <= halfCashbackDays { return .ok(.half) }
            return .ok(.quarter)
        }

        // Mes anterior: solo los primeros dias del mes, y sin cashback.
        let monthsApart = (todayYear - fechaYear) * 12 + (todayMonth - fechaMonth)
        if monthsApart == 1 && todayDay <= previousMonthGraceDays {
            return .ok(.none)
        }
        return .tooOld
    }

    /// Texto para la pantalla de revision cuando el cashback no es completo.
    static func tierMessage(_ tier: CashbackTier) -> String? {
        switch tier {
        case .full:
            return nil
        case .half:
            return "Registraste esta factura entre \(fullCashbackDays + 1) y \(halfCashbackDays) días después de la compra: ganas la mitad del cashback. Regístrala el mismo día para ganarlo completo."
        case .quarter:
            return "Registraste esta factura más de \(halfCashbackDays) días después de la compra: ganas un cuarto del cashback. Regístrala el mismo día para ganarlo completo."
        case .none:
            return "Esta factura es del mes pasado: se registra el gasto en su fecha, pero ya no gana cashback."
        }
    }
}
