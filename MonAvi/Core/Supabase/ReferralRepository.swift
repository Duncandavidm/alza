import Foundation
import Supabase

/// Largo exacto de un codigo de invitacion (constante global: no queda
/// atada al MainActor del repositorio).
private let referralCodeLength = 6

/// Resumen de "Invita amigos" (RPC `my_referral_summary`): el codigo
/// propio, cuantas personas lo usaron y si el usuario todavia puede
/// usar el codigo de alguien mas.
struct ReferralSummary: Decodable, Equatable {
    let code: String
    /// Personas que se unieron con tu codigo.
    let invited: Int
    /// Invitaciones que ya dieron puntos (el invitado registro su
    /// primera factura y se confirmo).
    let rewarded: Int
    /// Invitaciones que todavia esperan esa primera factura.
    let pending: Int
    /// Puntos ganados por invitar.
    let pointsEarned: Int
    /// true si todavia puede usar el codigo de un amigo (primeros 7
    /// dias y sin haber usado uno antes).
    let canApplyCode: Bool
    /// El codigo de invitacion que uso, si uso uno.
    let appliedCode: String?

    enum CodingKeys: String, CodingKey {
        case code
        case invited
        case rewarded
        case pending
        case pointsEarned = "points_earned"
        case canApplyCode = "can_apply_code"
        case appliedCode = "applied_code"
    }

    static let empty = ReferralSummary(
        code: "",
        invited: 0,
        rewarded: 0,
        pending: 0,
        pointsEarned: 0,
        canApplyCode: false,
        appliedCode: nil
    )
}

extension ReferralSummary {
    /// Decodificado tolerante: los contadores en null -> 0.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        invited = try container.decodeIfPresent(Int.self, forKey: .invited) ?? 0
        rewarded = try container.decodeIfPresent(Int.self, forKey: .rewarded) ?? 0
        pending = try container.decodeIfPresent(Int.self, forKey: .pending) ?? 0
        pointsEarned = try container.decodeIfPresent(Int.self, forKey: .pointsEarned) ?? 0
        canApplyCode = try container.decodeIfPresent(Bool.self, forKey: .canApplyCode) ?? false
        appliedCode = try container.decodeIfPresent(String.self, forKey: .appliedCode)
    }
}

/// Programa de referidos (RPCs `my_referral_summary` y
/// `apply_referral_code`). Las reglas (100 puntos para quien se une,
/// 200 para quien invita, tope de invitaciones premiadas) las aplica el
/// servidor; aqui solo se leen y se manda el codigo.
@MainActor
final class ReferralRepository {
    static let shared = ReferralRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    /// Largo exacto de un codigo de invitacion.
    static let codeLength = referralCodeLength

    /// La RPC devuelve una tabla de una sola fila.
    func fetchSummary() async throws -> ReferralSummary {
        let rows: [ReferralSummary] = try await supabase
            .rpc("my_referral_summary")
            .execute()
            .value
        return rows.first ?? .empty
    }

    private struct ApplyParams: Encodable {
        let pCode: String
        enum CodingKeys: String, CodingKey { case pCode = "p_code" }
    }

    /// Lanza el error de Postgres con el mensaje en espanol de la RPC
    /// ("Ese código no existe", etc.) — ver `userMessage(for:)`.
    func apply(code: String) async throws {
        let cleaned = Self.normalized(code)
        try await supabase
            .rpc("apply_referral_code", params: ApplyParams(pCode: cleaned))
            .execute()
    }

    /// Mayusculas, sin espacios y solo letras/numeros, maximo 6.
    nonisolated static func normalized(_ text: String) -> String {
        let allowed = text.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(referralCodeLength))
    }

    /// El mensaje que armo la RPC (ya en espanol) si es un error de
    /// Postgres; si no, un texto generico.
    nonisolated static func userMessage(for error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            let message = postgrestError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return message
            }
        }
        return "No se pudo usar el código. Revisa tu conexión e inténtalo de nuevo."
    }
}
