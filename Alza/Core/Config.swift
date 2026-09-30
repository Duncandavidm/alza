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

    /// TODO(David): Client ID (tipo iOS) de un proyecto en Google Cloud
    /// Console, habilitado para "Sign in with Google". Debe coincidir con
    /// el REVERSED_CLIENT_ID puesto en Info.plist.
    static let googleSignInClientId = "TODO-google-oauth-client-id.apps.googleusercontent.com"
}
