import Foundation

/// Texto traducible que la app arma en código (1.1.0). La llave es el texto
/// en español con %@ donde van los datos; la traducción vive en
/// Localizable.xcstrings. Sin traducción, queda el español.
///
///     L("Llevas %@ en gastos", monto)
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    guard !args.isEmpty else { return format }
    return String(format: format, locale: Locale.monavi, arguments: args)
}
