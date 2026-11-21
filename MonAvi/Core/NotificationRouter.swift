import Foundation

/// A que pantalla lleva tocar una notificacion. Las push del servidor
/// traen `"screen": "points"` (ver verify-dgi-receipt) o
/// `"screen": "rewards"` (aviso diario de premios desbloqueados) en el
/// payload; llega como `userInfo["screen"]`. Tambien `"redemptions"`
/// (regalos y codigos en "Mis canjes") y `"home"` (solo abre la app en
/// Hoy, sin hoja encima).
/// Abrir "Pagar tarjeta / deuda" con esa deuda elegida.
struct CardPaymentRequest: Identifiable, Equatable {
    let id = UUID()
    let debtId: UUID?
}

enum NotificationDestination: String, Identifiable {
    case points
    case rewards
    case redemptions

    var id: String { rawValue }
}

/// Guarda el destino de la ultima notificacion tocada hasta que la
/// pantalla principal (DashboardTabView) lo muestre. Si la app estaba
/// cerrada o el usuario aun no inicia sesion, el destino espera aqui y se
/// abre en cuanto aparece la pantalla principal.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published var destination: NotificationDestination?

    /// Pedido pendiente de abrir "Registrar con voz" (ver
    /// `requestVoiceCapture()`). Igual que `destination`, espera aqui si la
    /// app estaba cerrada hasta que aparece la pantalla principal.
    @Published private(set) var voiceCaptureRequestedAt: Date?

    /// true mientras la pantalla de captura por voz esta abierta. Hoy
    /// (DayJournalView) lo observa para recargar el dia al cerrarla.
    @Published var isVoiceCapturePresented = false

    /// "Pagar tarjeta" pedido desde el aviso del dia de pago.
    @Published var cardPayment: CardPaymentRequest?

    func open(screen: String?, userInfo: [AnyHashable: Any] = [:]) {
        guard let screen else { return }
        let normalized = screen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "card_payment" {
            destination = nil
            let id = (userInfo["debtId"] as? String).flatMap(UUID.init(uuidString:))
            cardPayment = CardPaymentRequest(debtId: id)
            return
        }
        if normalized == "home" {
            // La app abre en Hoy: basta con cerrar la hoja que hubiera.
            destination = nil
            return
        }
        guard let destination = NotificationDestination(rawValue: normalized) else { return }
        self.destination = destination
    }
}

extension NotificationRouter {
    /// Cuanto tiempo vale un pedido de "registrar con voz" (Atajo, Siri o
    /// Tocar atrás) que todavia no se pudo mostrar. Si en ese rato la
    /// pantalla principal no aparece (ej. el usuario quedo en el paywall o
    /// en el segundo paso de verificacion), se descarta: no queremos que el
    /// microfono se abra solo minutos despues.
    static let voiceCaptureRequestTTL: TimeInterval = 90

    /// Lo llama `RecordByVoiceIntent` (y "Probar ahora" en la guia):
    /// DashboardTabView abre la pantalla de captura por voz en cuanto
    /// aparece, o de una vez si ya estaba en pantalla.
    func requestVoiceCapture() {
        voiceCaptureRequestedAt = Date()
    }

    /// true (y limpia el pedido) si hay un pedido vigente por mostrar.
    func consumeVoiceCaptureRequest() -> Bool {
        guard let requestedAt = voiceCaptureRequestedAt else { return false }
        voiceCaptureRequestedAt = nil
        return Date().timeIntervalSince(requestedAt) <= Self.voiceCaptureRequestTTL
    }
}
