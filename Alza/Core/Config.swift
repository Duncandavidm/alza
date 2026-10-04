import Foundation

/// Configuracion del backend propio de Avi (proyecto Supabase nuevo,
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

    /// Plan Individual. NO tiene Apple Family Sharing activado a proposito
    /// (aunque el toggle nativo existe en App Store Connect) — si alguien
    /// quiere compartir acceso con otras personas, tiene que comprar el
    /// plan Familia (ver subscriptionProductIdFamily) en vez de compartir
    /// este gratis. Activar "En familia" en este producto en ASC es
    /// PERMANENTE (Apple no deja desactivarlo despues), asi que nunca lo
    /// actives aqui ni en el anual.
    static let subscriptionProductId = "app.alza.sub.pro"

    /// MISMO grupo de suscripcion "Avi Pro" que `subscriptionProductId`
    /// (para que StoreKit los trate como planes intercambiables del mismo
    /// Pro, no como dos suscripciones separadas). $74.99/año (~$6.25/mes).
    ///
    /// OJO: termina en punto ("annual.") a proposito — asi quedo creado en
    /// App Store Connect (typo de origen) y el Product ID NUNCA se puede
    /// editar despues de creado. David decidio dejarlo asi en vez de
    /// borrar y recrear el producto, asi que este punto es permanente.
    static let subscriptionProductIdAnnual = "app.alza.sub.pro.annual."

    /// Plan "Familia": a diferencia de "En familia" (Apple Family Sharing,
    /// que SOLO deja compartir gratis el plan individual), este es un
    /// producto de suscripcion propio y mas caro que habilita hasta 5
    /// invitados via codigo (ver FamilyGroupService) — cada quien con su
    /// propia cuenta, heredando el acceso Pro del dueno del grupo. NO
    /// actives "En familia" en estos dos productos en App Store Connect:
    /// el cobro extra viene de ser un producto distinto, no de ese toggle.
    /// $14.99/mes ($134.99/año equivalente ~$11.25/mes).
    ///
    /// OJO: subscriptionProductIdFamily termina en punto ("family.") y
    /// subscriptionProductIdFamilyAnnual dice "anual" (una sola "n", no
    /// "annual") — ambos typos de origen en App Store Connect, igual de
    /// permanentes que el de arriba.
    static let subscriptionProductIdFamily = "app.alza.sub.pro.family."
    static let subscriptionProductIdFamilyAnnual = "app.alza.sub.pro.family.anual"

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
    /// propio para Avi, cambialo aqui.
    static let supportEmail = "soporte@avi.app"
}
