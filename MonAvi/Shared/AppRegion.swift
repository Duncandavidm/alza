import Foundation

/// País de la persona y su moneda (1.0.6). Se guarda en el perfil
/// (profiles.country) y en el App Group, para que los widgets también
/// muestren los montos en la moneda correcta.
///
/// Los montos no se convierten: la moneda solo cambia cómo se muestran y
/// en qué moneda se crean las cuentas nuevas.
enum AppCountry: String, Codable, CaseIterable, Identifiable, Hashable {
    case panama = "PA"
    case colombia = "CO"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .panama: return "🇵🇦"
        case .colombia: return "🇨🇴"
        }
    }

    var name: String {
        switch self {
        case .panama: return "Panamá"
        case .colombia: return "Colombia"
        }
    }

    var currencyCode: String {
        switch self {
        case .panama: return "USD"
        case .colombia: return "COP"
        }
    }

    var currencyName: String {
        switch self {
        case .panama: return "Dólar estadounidense (USD)"
        case .colombia: return "Peso colombiano (COP)"
        }
    }

    /// "🇵🇦 Panamá"
    var label: String { "\(flag) \(name)" }

    /// Decimales que se muestran (el peso colombiano se usa sin centavos).
    var fractionDigits: Int { self == .colombia ? 0 : 2 }

    /// Ejemplo de monto para los campos de texto.
    var amountExample: String { self == .colombia ? "50000" : "52.30" }

    /// Locale para formatear: Panamá conserva el formato de siempre (el del
    /// idioma de la app); Colombia usa "$ 50.000".
    var formatLocale: Locale? {
        switch self {
        case .panama: return nil
        case .colombia: return Locale(identifier: "es_CO")
        }
    }

    // MARK: - País actual

    private static let storageKey = "monavi.country"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.app.monavi.shared") }

    /// El país de la cuenta abierta (Panamá si aún no se sabe).
    static var current: AppCountry {
        get {
            defaults?.string(forKey: storageKey).flatMap(AppCountry.init(rawValue:)) ?? .panama
        }
        set {
            defaults?.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// Colombia se ofrece solo cuando se activa desde el panel
    /// (app_config.colombia_enabled, leído con get_app_flags). Apagado por
    /// defecto: sin conexión o sin respuesta, la app se queda en Panamá.
    private static let colombiaKey = "monavi.colombiaEnabled"
    static var colombiaEnabled: Bool {
        get { defaults?.bool(forKey: colombiaKey) ?? false }
        set { defaults?.set(newValue, forKey: colombiaKey) }
    }

    /// Países que se pueden elegir. Quien ya está en Colombia lo sigue
    /// viendo aunque se apague (para poder volver a Panamá).
    static var available: [AppCountry] {
        colombiaEnabled || current == .colombia ? allCases : [.panama]
    }

    /// Para la primera pantalla: el país de la región del teléfono, si es
    /// uno de los disponibles.
    static var suggested: AppCountry {
        colombiaEnabled && Locale.current.region?.identifier == "CO" ? .colombia : .panama
    }

    /// Monto escrito por la persona → Decimal. En Colombia el punto y la
    /// coma son separadores de miles ("50.000" = cincuenta mil; el peso se
    /// usa sin centavos). En Panamá, igual que siempre ("52,30" = 52.30).
    static func parseAmount(_ text: String) -> Decimal? {
        if current == .colombia {
            let digits = text.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "")
            return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
        }
        return Decimal(string: text.replacingOccurrences(of: ",", with: "."))
    }

    /// Al cerrar sesión: la siguiente cuenta vuelve a elegir.
    static func reset() {
        defaults?.removeObject(forKey: storageKey)
    }
}

// MARK: - Formato de montos en la moneda del país

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// `Text(amount, format: .appCurrency)` → "USD 52.30" o "$ 50.000".
    static var appCurrency: Decimal.FormatStyle.Currency {
        let country = AppCountry.current
        var style = Decimal.FormatStyle.Currency(code: country.currencyCode)
        if let locale = country.formatLocale {
            style = style.locale(locale).precision(.fractionLength(country.fractionDigits))
        }
        return style
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    static var appCurrency: FloatingPointFormatStyle<Double>.Currency {
        let country = AppCountry.current
        var style = FloatingPointFormatStyle<Double>.Currency(code: country.currencyCode)
        if let locale = country.formatLocale {
            style = style.locale(locale).precision(.fractionLength(country.fractionDigits))
        }
        return style
    }
}

extension FormatStyle where Self == IntegerFormatStyle<Int>.Currency {
    static var appCurrency: IntegerFormatStyle<Int>.Currency {
        let country = AppCountry.current
        var style = IntegerFormatStyle<Int>.Currency(code: country.currencyCode)
        if let locale = country.formatLocale {
            style = style.locale(locale).precision(.fractionLength(country.fractionDigits))
        }
        return style
    }
}
