import Foundation

/// A que pantalla lleva tocar una notificacion. Las push del servidor
/// traen `"screen": "points"` (ver verify-dgi-receipt) o
/// `"screen": "rewards"` (aviso diario de premios desbloqueados) en el
/// payload; llega como `userInfo["screen"]`. Tambien `"redemptions"`
/// (regalos y codigos en "Mis canjes") y `"home"` (solo abre la app en
/// Hoy, sin hoja encima).
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

    func open(screen: String?) {
        guard let screen else { return }
        let normalized = screen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "home" {
            // La app abre en Hoy: basta con cerrar la hoja que hubiera.
            destination = nil
            return
        }
        guard let destination = NotificationDestination(rawValue: normalized) else { return }
        self.destination = destination
    }
}
