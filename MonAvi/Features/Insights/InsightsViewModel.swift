import Foundation
import Supabase

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var insights: [AIInsight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var isAsking = false
    @Published private(set) var lastAnswer: String?
    /// Preguntas de "Pregúntale" que le quedan este mes (RPC my_ai_quota);
    /// nil mientras no se sepa o si la RPC falla (no se muestra nada).
    @Published private(set) var askQuota: AIQuotaEntry?
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            insights = try await supabase
                .from("ai_insights")
                .select()
                .eq("user_id", value: userId)
                .eq("dismissed", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudieron cargar tus insights: \(error.localizedDescription)"
        }
    }

    /// Llama a la Edge Function generate-insights, que lee las cuentas y
    /// movimientos del usuario, se lo manda a un LLM, y guarda el resultado
    /// en ai_insights (con la service role key, no con la sesion del usuario).
    func generateInsights(userId: UUID) async {
        guard await AIConsentCenter.shared.requestIfNeeded() else {
            errorMessage = AIConsentCenter.declinedMessage
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        struct Payload: Encodable {
            let userId: String
        }

        do {
            // Si ya se generaron hoy (1 por dia), la funcion responde
            // {inserted: 0, cached: true}: no es error, solo se recarga la
            // lista que ya existe.
            _ = try await supabase.functions.invoke(
                "generate-insights",
                options: FunctionInvokeOptions(body: Payload(userId: userId.uuidString))
            )
            await refresh(userId: userId)
        } catch {
            errorMessage = Self.friendlyAIError(error, action: "generar tus insights")
        }
    }

    /// "Informes con IA": el usuario pregunta algo puntual en lenguaje
    /// normal y Claude responde con los numeros reales del negocio
    /// (Edge Function ask-finances). No guarda nada, solo responde.
    func ask(userId: UUID, question: String) async {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard await AIConsentCenter.shared.requestIfNeeded() else {
            errorMessage = AIConsentCenter.declinedMessage
            return
        }
        isAsking = true
        defer { isAsking = false }

        struct Payload: Encodable { let userId: String; let question: String }
        struct Response: Decodable { let answer: String }

        do {
            let response: Response = try await supabase.functions.invoke(
                "ask-finances",
                options: FunctionInvokeOptions(body: Payload(userId: userId.uuidString, question: question))
            )
            lastAnswer = response.answer
        } catch {
            errorMessage = Self.friendlyAIError(error, action: "responder tu pregunta")
        }
    }

    /// Lee cuantas preguntas de ask-finances le quedan al usuario.
    func refreshAskQuota() async {
        do {
            let quotas: [String: AIQuotaEntry] = try await supabase
                .rpc("my_ai_quota")
                .execute()
                .value
            askQuota = quotas["ask-finances"]
        } catch {
            askQuota = nil
        }
    }

    /// El cliente no debe ver "Edge Function returned a non-2xx status
    /// code: 500": un error del servidor de IA se explica en palabras
    /// normales; el detalle tecnico queda en los logs de Supabase.
    static func friendlyAIError(_ error: Error, action: String) -> String {
        // Cupo de uso justo / presupuesto diario: el servidor ya manda el
        // mensaje en español ("Usaste tus 100 preguntas de este mes...").
        if let serverMessage = AIErrorMessage.userMessage(from: error) {
            return serverMessage
        }
        if let functionsError = error as? FunctionsError, case .httpError(let code, _) = functionsError {
            if code == 429 {
                return "Hiciste muchas consultas seguidas. Espera un momento e intenta de nuevo."
            }
            if code >= 500 {
                return "El asistente de IA no está disponible en este momento. Intenta de nuevo más tarde."
            }
        }
        if (error as? URLError) != nil {
            return "No hay conexión a internet. Revisa tu conexión e intenta de nuevo."
        }
        return "No se pudo \(action). Intenta de nuevo más tarde."
    }

    func clearAnswer() {
        lastAnswer = nil
    }

    func dismiss(_ insight: AIInsight) async {
        insights.removeAll { $0.id == insight.id }
        _ = try? await supabase
            .from("ai_insights")
            .update(["dismissed": true])
            .eq("id", value: insight.id)
            .execute()
    }
}
