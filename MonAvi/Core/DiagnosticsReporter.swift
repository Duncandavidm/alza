import Foundation
import MetricKit
import Supabase

/// Suscriptor de MetricKit — Apple junta crashes, hangs y excepciones de
/// CPU/disco/memoria durante uso real (~24h de ventana) y los entrega aqui
/// una vez al dia, sin que haga falta ningun SDK de terceros. Como
/// MetricKit no tiene dashboard propio, cada reporte se sube tal cual (su
/// JSON nativo) a la tabla `app_diagnostics` de nuestro propio Supabase,
/// para revisarlos directo ahi.
///
/// Los crashes "duros" tambien quedan disponibles sin este codigo: Xcode
/// Organizer -> Crashes/Metrics los junta automaticamente para cualquier
/// build distribuido por TestFlight o App Store.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    private let supabase = SupabaseManager.shared.client

    private override init() {}

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            upload(kind: "metric", data: payload.jsonRepresentation())
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            upload(kind: "diagnostic", data: payload.jsonRepresentation())
        }
    }

    private func upload(kind: String, data: Data) {
        Task {
            // Best-effort: si no hay sesion o falla la subida, el reporte
            // simplemente se pierde — nunca debe afectar nada mas de la app.
            guard let userId = try? await supabase.auth.session.user.id else { return }

            do {
                let payloadJSON = try JSONDecoder().decode(AnyJSON.self, from: data)
                let report = NewAppDiagnosticReport(
                    userId: userId,
                    kind: kind,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    payload: payloadJSON
                )
                try await supabase.from("app_diagnostics").insert(report).execute()
            } catch {
                // Sin reintentos: el proximo payload diario de MetricKit cubre lo que se pierda.
            }
        }
    }
}
