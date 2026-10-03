import SwiftUI

/// "Mi familia": si compraste el plan Familia, aqui esta tu codigo de
/// invitacion y a quien ya invitaste; si alguien mas te invito a la suya,
/// aqui entras su codigo para unirte (sin pagar nada tu). Siempre visible
/// en Ajustes, sin importar que plan tengas — unirse con un codigo no
/// requiere suscripcion propia.
struct FamilyGroupView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = FamilyGroupViewModel()

    var body: some View {
        List {
            if let group = viewModel.group {
                if group.isOwner {
                    ownerSection(group)
                } else {
                    memberSection(group)
                }
            } else {
                joinSection
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AmadaiBrand.alert)
                }
            }
        }
        .navigationTitle("Mi familia")
        .overlay {
            if viewModel.isLoading && viewModel.group == nil {
                ProgressView()
            }
        }
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private func ownerSection(_ group: FamilyGroup) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Codigo de invitacion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.inviteCode)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

            ShareLink(item: "Unete a mi familia en Amadai con el codigo \(group.inviteCode) — entra en Ajustes > Mi familia dentro de la app.") {
                Label("Compartir codigo", systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text("Quien use este codigo (hasta 5 personas) obtiene acceso Pro completo, con su propia cuenta y datos — sin pagar nada por su cuenta.")
        }

        Section("Miembros (\(group.members.count)/5)") {
            if group.members.isEmpty {
                Text("Todavia no se ha unido nadie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(group.members) { member in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                        Text("Se unio el \(member.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.removeMember(member) }
                        } label: {
                            Label("Quitar", systemImage: "person.fill.xmark")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func memberSection(_ group: FamilyGroup) -> some View {
        Section {
            Label("Formas parte de la familia de \(group.ownerDisplayName)", systemImage: "person.2.fill")
        } footer: {
            Text("Tienes acceso Pro completo mientras sigas en este grupo y la suscripcion de quien te invito este activa.")
        }

        Section {
            Button(role: .destructive) {
                guard let userId = appState.currentUserId else { return }
                Task { await viewModel.leave(userId: userId) }
            } label: {
                if viewModel.isLeaving {
                    ProgressView()
                } else {
                    Text("Salir del grupo familiar")
                }
            }
            .disabled(viewModel.isLeaving)
        }
    }

    private var joinSection: some View {
        Section {
            TextField("Codigo de invitacion", text: $viewModel.inviteCodeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Button {
                Task { await viewModel.join() }
            } label: {
                if viewModel.isJoining {
                    ProgressView()
                } else {
                    Text("Unirme")
                }
            }
            .disabled(viewModel.isJoining || viewModel.inviteCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Unirte a una familia")
        } footer: {
            Text("Si alguien con el plan Familia de Amadai te paso su codigo, entralo aqui para obtener acceso Pro sin pagar nada tu. Si tu compraste el plan Familia, tu codigo aparece aqui apenas se active la suscripcion.")
        }
    }
}
