import Foundation
import Supabase

/// Para que movimientos se ofrece una categoria propia.
enum UserCategoryKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case gasto
    case ingreso
    case ambos

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gasto: return "Gasto"
        case .ingreso: return "Ingreso"
        case .ambos: return "Ambos"
        }
    }

    /// Si se ofrece al anotar una entrada (true) o una salida (false).
    func applies(isInflow: Bool) -> Bool {
        switch self {
        case .ambos: return true
        case .ingreso: return isInflow
        case .gasto: return !isInflow
        }
    }
}

/// Categoria creada por el usuario (tabla `user_categories`). Los
/// movimientos guardan solo el nombre en `transactions.category`.
struct UserCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID?
    var name: String
    var emoji: String
    var kind: UserCategoryKind
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case emoji
        case kind
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        emoji = (try container.decodeIfPresent(String.self, forKey: .emoji)) ?? "🏷️"
        // Un valor desconocido no debe romper toda la lista.
        let rawKind = (try container.decodeIfPresent(String.self, forKey: .kind)) ?? "gasto"
        kind = UserCategoryKind(rawValue: rawKind) ?? .gasto
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

@MainActor
final class UserCategoriesRepository {
    static let shared = UserCategoriesRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    /// `user_id` lo pone la base (default auth.uid()).
    private struct NewUserCategory: Encodable {
        let name: String
        let emoji: String
        let kind: String
    }

    private struct UserCategoryEditFields: Encodable {
        let name: String
        let emoji: String
        let kind: String
    }

    /// Las del usuario con sesion (la RLS filtra por dueno), por nombre.
    func fetchAll() async throws -> [UserCategory] {
        try await supabase
            .from("user_categories")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func add(name: String, emoji: String, kind: UserCategoryKind) async throws -> UserCategory {
        try await supabase
            .from("user_categories")
            .insert(NewUserCategory(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: emoji,
                kind: kind.rawValue
            ))
            .select()
            .single()
            .execute()
            .value
    }

    @discardableResult
    func update(_ category: UserCategory, name: String, emoji: String, kind: UserCategoryKind) async throws -> UserCategory {
        try await supabase
            .from("user_categories")
            .update(UserCategoryEditFields(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: emoji,
                kind: kind.rawValue
            ))
            .eq("id", value: category.id)
            .select()
            .single()
            .execute()
            .value
    }

    /// Los movimientos que ya la usan conservan el texto.
    func delete(_ category: UserCategory) async throws {
        try await supabase.from("user_categories").delete().eq("id", value: category.id).execute()
    }
}
