import SwiftUI

/// Apple exige (Guideline 5.1.1(v)) poder eliminar la cuenta desde
/// dentro de la app — este es ese flujo. Irreversible: pide escribir
/// "ELIMINAR" para habilitar el boton, en vez de un simple toggle, por
/// que es mas destructivo que cualquier otra accion de la app.
struct DeleteAccountView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmationText = ""
    @State private var familyGroup: FamilyGroup?
    @State private var isLoadingFamilyGroup = true
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var isConfirmed: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ELIMINAR"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("⚠️").font(.largeTitle)
                    Text("Esto no se puede deshacer")
                        .font(.title3.weight(.bold))
                    Text("Se borran para siempre tus cuentas, movimientos, presupuestos, deudas, metas de ahorro, facturas, puntos y todo lo demas que hayas registrado en MonAvi. No hay forma de recuperarlo despues.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if let familyGroup, familyGroup.isOwner, !familyGroup.members.isEmpty {
                Section {
                    Text("Eres dueño de un grupo familiar con \(familyGroup.members.count) persona\(familyGroup.members.count == 1 ? "" : "s"). Si eliminas tu cuenta, \(familyGroup.members.count == 1 ? "esa persona pierde" : "esas personas pierden") su acceso Pro de inmediato.")
                        .font(.subheadline)
                        .foregroundStyle(MonAviBrand.alert)
                }
            }

            Section {
                Text("Escribe ELIMINAR para confirmar")
                    .font(.subheadline)
                TextField("ELIMINAR", text: $confirmationText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    if isDeleting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Eliminar mi cuenta para siempre")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isConfirmed || isDeleting)
            }
        }
        .navigationTitle("Eliminar cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoadingFamilyGroup {
                ProgressView()
            }
        }
        .task { await loadFamilyGroup() }
    }

    private func loadFamilyGroup() async {
        isLoadingFamilyGroup = true
        defer { isLoadingFamilyGroup = false }
        familyGroup = try? await FamilyGroupService.shared.fetchMyGroup()
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appState.deleteAccount()
        } catch {
            errorMessage = "No se pudo eliminar la cuenta: \(error.localizedDescription)"
        }
    }
}
