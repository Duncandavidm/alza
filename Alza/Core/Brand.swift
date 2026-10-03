import SwiftUI

/// La paleta y tipografia oficial de la marca Amadai — un solo lugar para
/// no repetir valores hex sueltos por toda la app (y para que "cambiar
/// el color de marca" sea editar un archivo, no buscar en 15).
///
/// `primary` es el verde/teal EXACTO del logo (sampleado del PNG:
/// #00A585), tambien puesto como AccentColor del proyecto. El resto de
/// la paleta viene del prompt original de la version web de Amadai (el
/// nombre del proyecto cambio despues, la paleta no).
enum AmadaiBrand {
    /// El verde/teal de marca.
    static let primary = Color(hex: "#00A585") ?? .accentColor

    /// Variante mas oscura del verde de marca, para el extremo oscuro de
    /// degradados (headers, superficies elevadas) en vez de negro plano.
    static let primaryDark = Color(hex: "#027A64") ?? primary

    /// Superficie oscura de marca: charcoal con tinte teal, no negro
    /// plano — "no me gusta ese negro" quedo resuelto con esto.
    static let darkSurface = Color(hex: "#0E1614") ?? .black

    /// Texto claro sobre darkSurface / sobre el degradado de marca.
    static let onDarkSurface = Color(hex: "#F2F5F4") ?? .white

    /// Alerta/negativo con tono de marca — rojo ladrillo apagado, nunca
    /// rojo neon generico.
    static let alert = Color(hex: "#B5453A") ?? .red

    /// Bordes/separadores neutros con tinte de marca.
    static let border = Color(hex: "#E4E9E7") ?? Color(.separator)

    /// El degradado que viste el header del login y otras superficies de
    /// marca "oscuras": de teal a charcoal-teal, nunca negro plano.
    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [primaryDark, darkSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Tipografia de marca. SwiftUI no deja embeber Inter/Manrope (las
    /// que pedia el prompt original) sin agregar archivos .ttf reales al
    /// proyecto y registrarlos en Info.plist — no se pudo hacer con
    /// confianza sin poder compilar/probar en este entorno. En su lugar
    /// se usa el design "rounded" del sistema (SF Pro Rounded), que da
    /// la misma energia moderna y geometrica que pedia el prompt
    /// ("el mark del logo es moderno/geometrico, la tipografia debe
    /// matchear esa energia") sin depender de assets adicionales.
    static let fontDesign: Font.Design = .rounded
}
