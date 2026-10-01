import Foundation
import Supabase

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var insights: [AIInsight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var isAsking = false
    @Published private(set) var lastAnswer: String?
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
        isGenerating = true
        defer { isGenerating = false }

        struct Payload: Encodable {
            let userId: String
        }

        do {
            _ = try await supabase.functions.invoke(
                "generate-insights",
                options: FunctionInvokeOptions(body: Payload(userId: userId.uuidString))
            )
            await refresh(userId: userId)
        } catch {
            errorMessage = "No se pudieron generar insights nuevos: \(error.localizedDescription)"
        }
    }

    /// "Informes con IA": el usuario pregunta algo puntual en lenguaje
    /// normal y Claude responde con los numeros reales del negocio
    /// (Edge Function ask-finances). No guarda nada, solo responde.
    func ask(userId: UUID, question: String) async {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
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
            errorMessage = "No se pudo responder tu pregunta: \(error.localizedDescription)"
        }
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
