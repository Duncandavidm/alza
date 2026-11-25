import AppIntents
import Foundation

/// Lo que muestra el widget "Tu día" (pantalla de inicio): gastado hoy y en
/// el mes, lo que te queda del mes y los ultimos movimientos. Lo escribe la
/// app (DayWidgetUpdater) en el App Group compartido; el widget solo lo lee.
///
/// Vive en ambos targets (MonAvi y MonAviWidget): ver project.yml.
struct DayWidgetSnapshot: Codable {
    struct Recent: Codable, Identifiable, Hashable {
        let id: String
        let title: String
        let emoji: String
        let amount: Double
        let isIncome: Bool
    }

    let todaySpent: Double
    let todayCount: Int
    let monthSpent: Double
    /// Ingresos del mes menos gastos del mes; nil si no hay ingresos anotados.
    let monthLeft: Double?
    let recent: [Recent]
    let updatedAt: Date

    private static let storageKey = "day_widget_snapshot_v1"
    private static let hideAmountsKey = "day_widget_hide_amounts"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: BudgetWidgetSnapshot.appGroupId) }

    static func load() -> DayWidgetSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DayWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.storageKey)
    }

    /// Al cerrar sesion: el widget no debe seguir mostrando los datos de
    /// la cuenta anterior.
    static func clear() {
        defaults?.removeObject(forKey: storageKey)
        defaults?.removeObject(forKey: hideAmountsKey)
    }

    /// El ojo del widget: oculta los montos (por privacidad).
    static var hideAmounts: Bool {
        get { defaults?.bool(forKey: hideAmountsKey) ?? false }
        set { defaults?.set(newValue, forKey: hideAmountsKey) }
    }

    /// Si el snapshot es de otro dia, "hoy" todavia no tiene movimientos.
    func isFromToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(updatedAt, inSameDayAs: now)
    }

    static let widgetKind = "MonAviDayWidget"
}

/// Boton del ojo en el widget "Tu día": muestra u oculta los montos.
struct ToggleWidgetAmountsIntent: AppIntent {
    static var title: LocalizedStringResource = "Mostrar u ocultar montos del widget"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        DayWidgetSnapshot.hideAmounts.toggle()
        return .result()
    }
}
