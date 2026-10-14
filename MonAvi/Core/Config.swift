import Foundation

/// Configuracion del backend propio de MonAvi (proyecto Supabase nuevo,
/// sin relacion con maday). Los valores de Supabase son publicos por diseno
/// (equivalentes a la publishable key de maday) y estan pensados para vivir
/// en el binario del cliente.
enum Config {
    static let supabaseURL = URL(string: "https://jfhevxztsvnlsuwkwtmd.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_Sc7czB2BxbUwbUyKCXvmRg_y32J1KQi"

    /// Plan Individual. NO tiene Apple Family Sharing activado a proposito
    /// (aunque el toggle nativo existe en App Store Connect) — si alguien
    /// quiere compartir acceso con otras personas, tiene que comprar el
    /// plan Familia (ver subscriptionProductIdFamily) en vez de compartir
    /// este gratis. Activar "En familia" en este producto en ASC es
    /// PERMANENTE (Apple no deja desactivarlo despues), asi que nunca lo
    /// actives aqui ni en el anual.
    static let subscriptionProductId = "app.monavi.sub.pro"

    /// MISMO grupo de suscripcion "MonAvi Pro" que `subscriptionProductId`
    /// (para que StoreKit los trate como planes intercambiables del mismo
    /// Pro, no como dos suscripciones separadas). $74.99/año (~$6.25/mes).
    static let subscriptionProductIdAnnual = "app.monavi.sub.pro.annual"

    /// Plan "Familia": a diferencia de "En familia" (Apple Family Sharing,
    /// que SOLO deja compartir gratis el plan individual), este es un
    /// producto de suscripcion propio y mas caro que habilita hasta 5
    /// invitados via codigo (ver FamilyGroupService) — cada quien con su
    /// propia cuenta, heredando el acceso Pro del dueno del grupo. NO
    /// actives "En familia" en estos dos productos en App Store Connect:
    /// el cobro extra viene de ser un producto distinto, no de ese toggle.
    /// $14.99/mes ($134.99/año equivalente ~$11.25/mes).
    static let subscriptionProductIdFamily = "app.monavi.sub.pro.family"
    static let subscriptionProductIdFamilyAnnual = "app.monavi.sub.pro.family.annual"

    /// Paginas reales en `docs/privacy.html` y `docs/terms.html`, servidas
    /// gratis por GitHub Pages (ver README para activarlo) — asi no
    /// dependen de comprar un dominio propio para pasar el review de Apple
    /// (App Store Review Guideline 3.1.2, obligatorio por tener
    /// suscripcion). La URL sigue diciendo "/alza/" porque asi se sigue
    /// llamando el repositorio en GitHub (renombrar el repo es un paso
    /// aparte, opcional) — no afecta el nombre que ve el cliente. Si mas
    /// adelante compras un dominio propio, apunta su DNS a GitHub Pages
    /// como dominio personalizado y cambia estas dos URLs.
    static let privacyPolicyURL = URL(string: "https://duncandavidm.github.io/alza/privacy.html")!
    static let termsOfUseURL = URL(string: "https://duncandavidm.github.io/alza/terms.html")!
    /// TODO(David): este dominio todavia no existe — cuando tengas uno
    /// propio para MonAvi, cambialo aqui.
    static let supportEmail = "soporte@monavi.app"
}
