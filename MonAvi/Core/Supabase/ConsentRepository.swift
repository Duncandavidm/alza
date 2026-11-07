import Foundation
import Supabase

/// Consentimientos del usuario (Ley 81 de 2019 de Panama). `user_consents`
/// es un registro de solo insercion: cada decision (aceptar o no) es una
/// fila nueva y la vista `current_consents` devuelve la ultima por
/// proposito para el usuario con sesion.
enum ConsentPurpose: String, Codable {
    case estudioMercado = "estudio_mercado"
    case programaRecompensas = "programa_recompensas"
    /// Push de promociones de comercios y marcas + bonos y regalos
    /// personalizados (cashback, productos gratis). Migracion 0040.
    case ofertas
}

struct ConsentDecision: Decodable, Hashable {
    let purpose: String
    let granted: Bool
    let textVersion: Int?
    let decidedAt: Date?

    enum CodingKeys: String, CodingKey {
        case purpose
        case granted
        case textVersion = "text_version"
        case decidedAt = "decided_at"
    }
}

@MainActor
final class ConsentRepository {
    static let shared = ConsentRepository()
    /// Version del texto que se le mostro al usuario (sube si cambia el texto).
    static let currentTextVersion = 1

    private let supabase = SupabaseManager.shared.client
    private init() {}

    private struct NewConsent: Encodable {
        let userId: UUID
        let purpose: String
        let granted: Bool
        let textVersion: Int
        let source: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case purpose
            case granted
            case textVersion = "text_version"
            case source
        }
    }

    /// Guarda una decision nueva (el servidor pone `decided_at`).
    func record(userId: UUID, purpose: ConsentPurpose, granted: Bool) async throws {
        try await supabase
            .from("user_consents")
            .insert(
                NewConsent(
                    userId: userId,
                    purpose: purpose.rawValue,
                    granted: granted,
                    textVersion: Self.currentTextVersion,
                    source: "app"
                )
            )
            .execute()
    }

    /// La ultima decision para ese proposito, o nil si nunca decidio.
    /// Lanza si hubo un error de red (para no confundirlo con "sin decision").
    func current(userId: UUID, purpose: ConsentPurpose) async throws -> ConsentDecision? {
        let rows: [ConsentDecision] = try await supabase
            .from("current_consents")
            .select("purpose, granted, text_version, decided_at")
            .eq("user_id", value: userId)
            .eq("purpose", value: purpose.rawValue)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}
