import Foundation
import Supabase

/// Logica de datos del grupo familiar (plan Familia): leer el grupo propio
/// o al que se pertenece, unirse con un codigo, salir, o (si eres el
/// dueno) sacar a alguien. El grupo en si lo crea solo el backend cuando
/// la suscripcion Familia del dueno queda activa — ver
/// supabase/migrations/0017_family_groups.sql.
@MainActor
final class FamilyGroupService {
    static let shared = FamilyGroupService()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    func fetchMyGroup() async throws -> FamilyGroup? {
        let rows: [FamilyGroupRow] = try await supabase
            .rpc("get_my_family_group")
            .execute()
            .value
        return FamilyGroup(rows: rows)
    }

    private struct JoinParams: Encodable {
        let pInviteCode: String
        enum CodingKeys: String, CodingKey { case pInviteCode = "p_invite_code" }
    }

    /// Lanza un error con el mensaje en espanol que arma la RPC
    /// (codigo invalido, grupo lleno, es tu propio grupo) si no se puede.
    func join(inviteCode: String) async throws {
        let normalized = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        _ = try await supabase
            .rpc("join_family_group", params: JoinParams(pInviteCode: normalized))
            .execute()
    }

    /// El propio miembro se sale del grupo al que pertenece.
    func leave(userId: UUID) async throws {
        try await removeMember(memberId: userId)
    }

    /// El dueno saca a un miembro de su grupo. (La RLS de family_members
    /// solo deja borrar la fila propia o, si eres el dueno, cualquiera de
    /// tu grupo — asi que esta misma funcion sirve para ambos casos.)
    func removeMember(memberId: UUID) async throws {
        try await supabase
            .from("family_members")
            .delete()
            .eq("member_id", value: memberId)
            .execute()
    }
}
