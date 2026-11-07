import Foundation

/// Configuracion del backend propio de MonAvi (proyecto Supabase nuevo,
/// sin relacion con maday). Los valores de Supabase son publicos por diseno
/// (equivalentes a la publishable key de maday) y estan pensados para vivir
/// en el binario del cliente.
enum Config {
    static let supabaseURL = URL(string: "https://jfhevxztsvnlsuwkwtmd.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_Sc7czB2BxbUwbUyKCXvmRg_y32J1KQi"

    /// Plan personal de MonAvi Pro (mensual). Cada persona paga su propia
    /// cuenta. NUNCA actives "En familia" (Apple Family Sharing) en este
    /// producto ni en el anual en App Store Connect: es PERMANENTE (Apple
    /// no deja desactivarlo despues).
    static let subscriptionProductId = "app.monavi.sub.pro"

    /// MISMO grupo de suscripcion "MonAvi Pro" que `subscriptionProductId`
    /// (para que StoreKit los trate como planes intercambiables del mismo
    /// Pro, no como dos suscripciones separadas). $74.99/año (~$6.25/mes).
    static let subscriptionProductIdAnnual = "app.monavi.sub.pro.annual"

    /// Privacidad y terminos (App Store Review Guideline 3.1.2), en el
    /// dominio de MonAvi. La version oficial vive en admin/legal/*.html y
    /// la sirve el panel; usa estas mismas URLs en App Store Connect.
    static let privacyPolicyURL = URL(string: "https://monavi.maday.app/privacy")!
    static let termsOfUseURL = URL(string: "https://monavi.maday.app/terms")!
    /// Soporte/FAQ publico (tambien es la "URL de soporte" de App Store
    /// Connect). El mailto de abajo es el contacto directo.
    static let supportURL = URL(string: "https://monavi.maday.app/support")!
    static let supportEmail = "hola@maday.app"

    /// Pagina de validacion de canjes para el comercio: el QR del canje
    /// abre `?code=<CODIGO>` con la camara de cualquier telefono y el
    /// cajero lo confirma con su PIN.
    static let redeemBaseURL = URL(string: "https://monavi.maday.app/canjear")!
}
