import Foundation

/// Configuracion del backend propio de Amadai (proyecto Supabase nuevo,
/// sin relacion con maday). Los valores de Supabase son publicos por diseno
/// (equivalentes a la publishable key de maday) y estan pensados para vivir
/// en el binario del cliente.
///
/// Nota sobre el nombre: el Bundle ID (`app.alza`) y los Product ID de
/// abajo siguen diciendo "alza" a proposito — son identificadores tecnicos
/// ya dados de alta en App Store Connect (la ficha, la suscripcion, el
/// build ya subido). Cambiarlos ahora equivaldria a empezar una app nueva
/// de cero ahi. Lo unico que cambia es el nombre visible (ver
/// CFBundleDisplayName en project.yml) y todo el texto que lee el cliente.
enum Config {
    static let supabaseURL = URL(string: "https://jfhevxztsvnlsuwkwtmd.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_Sc7czB2BxbUwbUyKCXvmRg_y32J1KQi"

    /// TODO(David): confirmar en App Store Connect una vez creada la ficha
    /// de la app y el producto de suscripcion. Debe coincidir exactamente
    /// con el Product ID configurado ahi.
    static let subscriptionProductId = "app.alza.sub.pro"

    /// TODO(David): crear este segundo producto en App Store Connect, en el
    /// MISMO grupo de suscripcion "Amadai Pro" que `subscriptionProductId`
    /// (para que StoreKit los trate como planes intercambiables del mismo
    /// Pro, no como dos suscripciones separadas) — ver README "App Store
    /// Connect" para el paso a paso. $5.99/mes ($71.88/año).
    static let subscriptionProductIdAnnual = "app.alza.sub.pro.annual"

    /// Plan "Familia": a diferencia de "En familia" (Apple Family Sharing,
    /// que SOLO deja compartir gratis el plan individual), este es un
    /// producto de suscripcion propio y mas caro que habilita hasta 5
    /// invitados via codigo (ver FamilyGroupService) — cada quien con su
    /// propia cuenta, heredando el acceso Pro del dueno del grupo. NO
    /// actives "En familia" en estos dos productos en App Store Connect:
    /// el cobro extra viene de ser un producto distinto, no de ese toggle.
    /// TODO(David): crear estos 2 productos en App Store Connect, mismo
    /// grupo "Amadai Pro" — $14.99/mes ($134.88/año equivalente ~$11.24/mes).
    static let subscriptionProductIdFamily = "app.alza.sub.pro.family"
    static let subscriptionProductIdFamilyAnnual = "app.alza.sub.pro.family.annual"

    /// Paginas reales en `docs/privacy.html` y `docs/terms.html`, servidas
    /// gratis por GitHub Pages (ver README para activarlo) — asi no
    /// dependen de comprar un dominio propio para pasar el review de Apple
    /// (App Store Review Guideline 3.1.2, obligatorio por tener
    /// suscripcion). La URL sigue diciendo "/alza/" porque asi se llama el
    /// repositorio en GitHub — no afecta el nombre que ve el cliente. Si
    /// mas adelante compras un dominio propio, apunta su DNS a GitHub
    /// Pages como dominio personalizado y cambia estas dos URLs.
    static let privacyPolicyURL = URL(string: "https://duncandavidm.github.io/alza/privacy.html")!
    static let termsOfUseURL = URL(string: "https://duncandavidm.github.io/alza/terms.html")!
    /// TODO(David): este dominio todavia no existe — cuando tengas uno
    /// propio para Amadai, cambialo aqui.
    static let supportEmail = "soporte@amadai.app"
}
