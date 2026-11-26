import AppIntents
import Foundation

/// Pedido de "abrir la camara para escanear una factura" que llega desde
/// fuera de la app: el widget de la pantalla bloqueada, el control del
/// Centro de control, Siri/Atajos o el enlace monavi://scan.
///
/// Vive en ambos targets (MonAvi y MonAviWidget, ver project.yml): el
/// control corre `OpenInvoiceScannerIntent`, que solo deja la marca en el
/// App Group compartido; la app abre la camara en cuanto aparece la
/// pantalla principal (DashboardTabView) y la marca se borra.
enum InvoiceScanRequest {
    static let appGroup = "group.app.monavi.shared"
    static let url = URL(string: "monavi://scan")!
    private static let key = "monavi.invoiceScanRequestedAt"
    /// Si la pantalla principal no aparece en este rato (ej. quedo en el
    /// paywall), el pedido se descarta: que la camara no se abra sola
    /// mucho despues.
    static let ttl: TimeInterval = 120

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Avisa a la app si el pedido se hizo con ella ya abierta (el intent
    /// corre dentro de la app); en el widget no tiene efecto.
    static let notification = Notification.Name("monavi.invoiceScanRequested")

    static func request(at date: Date = Date()) {
        defaults?.set(date.timeIntervalSince1970, forKey: key)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }

    /// true (y borra la marca) si hay un pedido vigente.
    static func consume(now: Date = Date()) -> Bool {
        guard let defaults, let stamp = defaults.object(forKey: key) as? Double else { return false }
        defaults.removeObject(forKey: key)
        return isFresh(requestedAt: Date(timeIntervalSince1970: stamp), now: now)
    }

    static func isFresh(requestedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(requestedAt)
        return age >= -5 && age <= ttl
    }

    /// monavi://scan (widget, enlaces).
    static func isScanURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "monavi" && (url.host?.lowercased() == "scan" || url.path == "/scan")
    }
}

/// "Escanear factura": abre MonAvi directo en la camara. Lo usan el
/// control del Centro de control / pantalla bloqueada (iOS 18), Siri y
/// Atajos.
struct OpenInvoiceScannerIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear factura"
    static var description = IntentDescription("Abre MonAvi con la cámara lista para escanear el QR de tu factura y ganar cashback.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        InvoiceScanRequest.request()
        return .result()
    }
}

// MARK: - Anotar gasto (Centro de control)

/// Pedido de "abrir Anotar movimiento" desde el botón del Centro de control
/// o de la pantalla bloqueada. Mismo mecanismo que InvoiceScanRequest: el
/// control deja la marca en el App Group y la app abre Anotar movimiento
/// en cuanto aparece la pantalla principal.
enum QuickAddRequest {
    private static let key = "monavi.quickAddRequestedAt"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: InvoiceScanRequest.appGroup) }
    static let notification = Notification.Name("monavi.quickAddRequested")

    static func request(at date: Date = Date()) {
        defaults?.set(date.timeIntervalSince1970, forKey: key)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }

    /// true (y borra la marca) si hay un pedido vigente.
    static func consume(now: Date = Date()) -> Bool {
        guard let defaults, let stamp = defaults.object(forKey: key) as? Double else { return false }
        defaults.removeObject(forKey: key)
        return InvoiceScanRequest.isFresh(requestedAt: Date(timeIntervalSince1970: stamp), now: now)
    }
}

/// "Anotar gasto": abre MonAvi en Anotar movimiento. Lo usa el botón del
/// Centro de control / pantalla bloqueada (iOS 18).
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar gasto"
    static var description = IntentDescription("Abre MonAvi listo para anotar un gasto o un ingreso.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QuickAddRequest.request()
        return .result()
    }
}
