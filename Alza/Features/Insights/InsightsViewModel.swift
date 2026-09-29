import Foundation
import Supabase

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var insights: [AIInsight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
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

    func dismiss(_ insight: AIInsight) async {
        insights.removeAll { $0.id == insight.id }
        try? await supabase
            .from("ai_insights")
            .update(["dismissed": true])
            .eq("id", value: insight.id)
            .execute()
    }
}
