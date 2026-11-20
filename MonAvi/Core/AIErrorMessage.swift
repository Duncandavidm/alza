import Foundation
import Supabase

/// Las Edge Functions de IA, cuando bloquean una llamada (cupo de uso justo,
/// presupuesto diario o demasiadas solicitudes seguidas), responden 429 con
/// `{"error": "<mensaje en español listo para mostrar>", "code": ...}`.
/// Este helper saca ese mensaje para mostrarlo tal cual al usuario.
enum AIErrorMessage {
    private struct Body: Decodable {
        let error: String?
        let code: String?
    }

    /// El mensaje del servidor si el error es un 429 de una Edge Function
    /// con `{"error": ...}` en el cuerpo; nil en cualquier otro caso.
    static func userMessage(from error: Error) -> String? {
        guard let functionsError = error as? FunctionsError,
              case .httpError(let code, let data) = functionsError,
              code == 429 else {
            return nil
        }
        return message(fromBody: data)
    }

    /// Decodifica `{"error": "..."}`; nil si el cuerpo no trae un texto util.
    static func message(fromBody data: Data) -> String? {
        guard !data.isEmpty,
              let body = try? JSONDecoder().decode(Body.self, from: data),
              let message = body.error?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }
}

/// Una entrada de la RPC `my_ai_quota()`, que devuelve un objeto por
/// Edge Function: {"ask-finances": {"used": 3, "limit": 100,
/// "remaining": 97, "period": "month", "resets_at": "..."}, ...}.
struct AIQuotaEntry: Decodable, Equatable {
    let used: Int
    let limit: Int
    let remaining: Int
    /// "month" o "day".
    let period: String

    /// Texto discreto para mostrar bajo el campo de pregunta.
    var askCaption: String {
        let left = max(remaining, 0)
        let when = period == "day" ? "hoy" : "este mes"
        switch left {
        case 0: return "Ya no te quedan preguntas \(when)"
        case 1: return "Te queda 1 pregunta \(when)"
        default: return "Te quedan \(left) preguntas \(when)"
        }
    }
}
