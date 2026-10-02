import Foundation
import Supabase

@MainActor
final class FeedbackViewModel: ObservableObject {
    @Published private(set) var suggestions: [FeedbackSuggestion] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            suggestions = try await supabase
                .from("feedback_suggestions")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudieron cargar tus sugerencias: \(error.localizedDescription)"
        }
    }

    func submit(_ new: NewFeedbackSuggestion) async throws {
        let created: FeedbackSuggestion = try await supabase
            .from("feedback_suggestions")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        suggestions.insert(created, at: 0)
    }

    func delete(_ suggestion: FeedbackSuggestion) async throws {
        try await supabase.from("feedback_suggestions").delete().eq("id", value: suggestion.id).execute()
        suggestions.removeAll { $0.id == suggestion.id }
    }
}
