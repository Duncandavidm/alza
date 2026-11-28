import Foundation

extension Locale {
    /// Formato de la app: español de Panamá, o inglés (EE. UU.) si la
    /// persona eligió English (1.1.0). Fechas y meses en el idioma de la app
    /// aunque el iPhone esté en otro.
    static var monavi: Locale { AppLanguage.current.formattingLocale }
}
