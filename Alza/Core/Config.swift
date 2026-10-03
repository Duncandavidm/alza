import Foundation

/// Configuracion del backend propio de Alza (proyecto Supabase nuevo,
/// sin relacion con maday). Los valores de Supabase son publicos por diseno
/// (equivalentes a la publishable key de maday) y estan pensados para vivir
/// en el binario del cliente.
enum Config {
    static let supabaseURL = URL(string: "https://jfhevxztsvnlsuwkwtmd.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_Sc7czB2BxbUwbUyKCXvmRg_y32J1KQi"

    /// TODO(David): confirmar en App Store Connect una vez creada la ficha
    /// de la app y el producto de suscripcion. Debe coincidir exactamente
    /// con el Product ID configurado ahi.
    static let subscriptionProductId = "app.alza.sub.pro"

    /// Paginas reales en `docs/privacy.html` y `docs/terms.html`, servidas
    /// gratis por GitHub Pages (ver README para activarlo) — asi no
    /// dependen de comprar el dominio alza.app para pasar el review de
    /// Apple (App Store Review Guideline 3.1.2, obligatorio por tener
    /// suscripcion). Si mas adelante compras alza.app, apunta su DNS a
    /// GitHub Pages como dominio personalizado y cambia estas dos URLs.
    static let privacyPolicyURL = URL(string: "https://duncandavidm.github.io/alza/privacy.html")!
    static let termsOfUseURL = URL(string: "https://duncandavidm.github.io/alza/terms.html")!
    static let supportEmail = "soporte@alza.app"
}
