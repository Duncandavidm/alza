import Foundation

/// Idioma de la app (1.1.0): español o inglés. Lo elige la persona en
/// Ajustes > Idioma (o en Ajustes de iOS > MonAvi > Idioma). Por defecto
/// sigue el idioma del iPhone; si no es inglés, español.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    /// Nombre en su propio idioma (así se reconoce aunque no entiendas el otro).
    var nativeName: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "English"
        }
    }

    private static let groupKey = "monavi.language"
    private static var group: UserDefaults? { UserDefaults(suiteName: "group.app.monavi.shared") }

    /// El idioma con que está corriendo la app (el del paquete de textos).
    static var current: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "es"
        return code.hasPrefix("en") ? .english : .spanish
    }

    /// Guarda la elección: iOS la aplica a toda la app al volver a abrirla.
    /// Los textos de SwiftUI cambian al instante (ver RootView: environment
    /// locale); los demás al reabrir.
    static func choose(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        group?.set(language.rawValue, forKey: groupKey)
    }

    /// Para el widget y lo que corre fuera de la app.
    static var stored: AppLanguage {
        group?.string(forKey: groupKey).flatMap(AppLanguage.init(rawValue:)) ?? current
    }

    /// Fechas, meses y números: español de Panamá o inglés (EE. UU.).
    var formattingLocale: Locale {
        switch self {
        case .spanish: return Locale(identifier: "es_PA")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// Reconocedores de voz a probar, en orden.
    var speechLocales: [String] {
        switch self {
        case .spanish: return ["es-PA", "es-419", "es-MX", "es-US", "es-CO", "es-ES"]
        case .english: return ["en-US", "en-GB", "en-CA", "en-AU"]
        }
    }
}
