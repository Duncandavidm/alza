import Foundation

/// Como da el banco la tasa: casi siempre al año (ej. 24% anual), a veces
/// al mes (2%). MonAvi guarda la mensual (`interest_rate_monthly`).
enum InterestPeriod: String, CaseIterable, Identifiable {
    case annual
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .annual: return L("Al año")
        case .monthly: return L("Al mes")
        }
    }
}

/// Cuentas de una tarjeta de credito (logica pura, probada en CreditCardMathTests).
enum CreditCardMath {
    /// `isMoney: false` para tasas de interes.
    static func parse(_ text: String, isMoney: Bool = true) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "$", with: "")
        // "0" es valido aqui (tarjeta sin usar, tasa 0%); el parser de montos no lo acepta.
        if let plain = Decimal(string: cleaned.replacingOccurrences(of: ",", with: ".")), plain == 0 { return 0 }
        return RecurringAmountParser.parse(cleaned, isMoney: isMoney)
    }

    /// Tasa mensual a guardar: la anual se divide entre 12.
    static func monthlyRate(_ text: String, period: InterestPeriod) -> Decimal? {
        guard let rate = parse(text, isMoney: false), rate >= 0 else { return nil }
        switch period {
        case .monthly: return rate
        case .annual: return (rate / 12).roundedTo(4)
        }
    }

    static func annualRate(monthly: Decimal) -> Decimal {
        (monthly * 12).roundedTo(2)
    }

    static func available(limit: Decimal?, used: Decimal?) -> Decimal? {
        guard let limit, limit > 0 else { return nil }
        return limit - (used ?? 0)
    }

    static func utilization(limit: Decimal?, used: Decimal?) -> Double? {
        guard let limit, limit > 0 else { return nil }
        return NSDecimalNumber(decimal: (used ?? 0) / limit).doubleValue
    }

    /// "Disponible $1,400.00 · usas el 30% del cupo".
    static func summary(limit: Decimal?, used: Decimal?) -> String? {
        guard let available = available(limit: limit, used: used),
              let use = utilization(limit: limit, used: used) else { return nil }
        if available < 0 {
            return L("Te pasaste del cupo por %@", "\(FinancialSnapshot.money(-available))")
        }
        return L("Disponible %@ · usas el %@ del cupo", "\(FinancialSnapshot.money(available))", "\(FinancialSnapshot.percent(use))")
    }

    /// "2% al mes (24% al año)".
    static func rateText(monthly: Decimal) -> String {
        L("%@%% al mes (%@%% al año)", "\(number(monthly))", "\(number(annualRate(monthly: monthly)))")
    }

    private static func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
