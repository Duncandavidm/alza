import Foundation

/// Un miembro invitado a un grupo familiar (nunca incluye al dueno).
struct FamilyGroupMember: Identifiable, Hashable {
    let id: UUID
    let fullName: String?
    let joinedAt: Date

    var displayName: String { fullName?.isEmpty == false ? fullName! : "Miembro" }
}

/// Refleja la fila que arma la RPC get_my_family_group para el usuario
/// actual — ya sea porque es el dueno (compro el plan Familia) o porque es
/// un miembro invitado (hereda el acceso Pro del dueno). nil si no
/// pertenece a ningun grupo familiar.
struct FamilyGroup: Identifiable {
    let id: UUID
    let inviteCode: String
    let ownerId: UUID
    let ownerFullName: String?
    let isOwner: Bool
    let members: [FamilyGroupMember]

    var ownerDisplayName: String { ownerFullName?.isEmpty == false ? ownerFullName! : "el dueno de la familia" }
    var hasOpenSlots: Bool { members.count < 5 }
}

/// Fila cruda que devuelve get_my_family_group (una por miembro, o una
/// sola con los campos de miembro en nil si el grupo todavia no tiene
/// ninguno) — se arma en FamilyGroup.init(rows:).
struct FamilyGroupRow: Decodable {
    let groupId: UUID
    let inviteCode: String
    let ownerId: UUID
    let ownerFullName: String?
    let isOwner: Bool
    let memberId: UUID?
    let memberFullName: String?
    let memberJoinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case ownerFullName = "owner_full_name"
        case isOwner = "is_owner"
        case memberId = "member_id"
        case memberFullName = "member_full_name"
        case memberJoinedAt = "member_joined_at"
    }
}

extension FamilyGroup {
    init?(rows: [FamilyGroupRow]) {
        guard let first = rows.first else { return nil }
        self.id = first.groupId
        self.inviteCode = first.inviteCode
        self.ownerId = first.ownerId
        self.ownerFullName = first.ownerFullName
        self.isOwner = first.isOwner
        self.members = rows.compactMap { row in
            guard let memberId = row.memberId, let joinedAt = row.memberJoinedAt else { return nil }
            return FamilyGroupMember(id: memberId, fullName: row.memberFullName, joinedAt: joinedAt)
        }
    }
}
