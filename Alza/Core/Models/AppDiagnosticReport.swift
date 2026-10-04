import Foundation
import Supabase

/// Lo que se sube a `app_diagnostics` — el payload es el JSON nativo que
/// entrega MetricKit (`MXMetricPayload`/`MXDiagnosticPayload`.jsonRepresentation()),
/// sin reinterpretarlo: David lo revisa directo en el dashboard de Supabase.
struct NewAppDiagnosticReport: Encodable {
    let userId: UUID
    let kind: String
    let appVersion: String?
    let osVersion: String?
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case kind
        case appVersion = "app_version"
        case osVersion = "os_version"
        case payload
    }
}
