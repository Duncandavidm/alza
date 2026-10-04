import Foundation

/// Snapshot minimo que la app principal escribe en el App Group
/// compartido cada vez que refresca los presupuestos. El widget de
/// pantalla de inicio corre en su propio proceso, sin sesion de Supabase
/// ni acceso al Keychain de la app — en vez de que el widget intente
/// autenticarse y pedir datos el solo, la app ya hizo el trabajo y deja
/// esto listo para leer.
///
/// Este archivo vive en ambos targets (Avi y AlzaWidget) — ver
/// project.yml, donde se lista explicitamente en las fuentes del widget
/// ademas de quedar incluido normalmente en las del target principal.
struct BudgetWidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String { category }
        let category: String
        let emoji: String
        let colorHex: String
        let spent: Double
        let limitAmount: Double
        let ratio: Double
    }

    let items: [Item]
    let updatedAt: Date

    /// TODO(David): si cambias este identifier, tiene que coincidir EXACTO
    /// con el App Group que actives en Signing & Capabilities para los
    /// targets Avi y AlzaWidget en Xcode (y que exista en tu cuenta de
    /// Apple Developer — con "Automatically manage signing" deberia
    /// crearse solo la primera vez que compiles con tu Team seleccionado).
    static let appGroupId = "group.app.alza.shared"
    private static let storageKey = "budget_widget_snapshot_v1"

    static func load() -> BudgetWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(BudgetWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupId) else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
