import Foundation

@MainActor
final class FamilyGroupViewModel: ObservableObject {
    @Published private(set) var group: FamilyGroup?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var inviteCodeInput = ""
    @Published private(set) var isJoining = false
    @Published private(set) var isLeaving = false

    private let service = FamilyGroupService.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            group = try await service.fetchMyGroup()
        } catch {
            errorMessage = "No se pudo cargar tu grupo familiar: \(error.localizedDescription)"
        }
    }

    /// El mensaje de error que vea el usuario viene directo del RAISE
    /// EXCEPTION de join_family_group (codigo invalido, grupo lleno, es tu
    /// propio grupo) — ya esta en espanol, listo para mostrar tal cual.
    func join() async {
        let code = inviteCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isJoining = true
        defer { isJoining = false }
        errorMessage = nil
        do {
            try await service.join(inviteCode: code)
            inviteCodeInput = ""
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leave(userId: UUID) async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await service.leave(userId: userId)
            group = nil
        } catch {
            errorMessage = "No se pudo salir del grupo: \(error.localizedDescription)"
        }
    }

    func removeMember(_ member: FamilyGroupMember) async {
        do {
            try await service.removeMember(memberId: member.id)
            await refresh()
        } catch {
            errorMessage = "No se pudo quitar a \(member.displayName): \(error.localizedDescription)"
        }
    }
}
