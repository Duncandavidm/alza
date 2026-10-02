import Foundation

/// Sugerencia u mejora que el cliente escribe desde Ajustes. Se guarda en
/// Supabase y David la revisa directo en el dashboard — no hace falta una
/// pantalla de admin dentro de la app para esto.
struct FeedbackSuggestion: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let message: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case message
        case createdAt = "created_at"
    }
}

struct NewFeedbackSuggestion: Encodable {
    let userId: UUID
    let message: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case message
    }
}
