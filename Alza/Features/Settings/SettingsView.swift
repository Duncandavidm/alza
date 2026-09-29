import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Suscripcion") {
                    switch appState.subscriptionStatus {
                    case .active(let expiresAt):
                        LabeledContent("Estado", value: "Activa")
                        if let expiresAt {
                            LabeledContent("Renueva", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    case .inGracePeriod:
                        LabeledContent("Estado", value: "En periodo de gracia")
                    case .expired:
                        LabeledContent("Estado", value: "Expirada")
                    case .revoked:
                        LabeledContent("Estado", value: "Revocada")
                    case .none, .unknown:
                        LabeledContent("Estado", value: "Sin suscripcion")
                    }

                    Button("Administrar suscripcion") {
                        Task { await appState.subscriptionStore.openManageSubscriptions() }
                    }

                    Button("Restaurar compras") {
                        Task {
                            await appState.subscriptionStore.restore()
                            await appState.refreshSubscriptionStatus()
                        }
                    }
                }

                Section {
                    Button("Cerrar sesion", role: .destructive) {
                        Task { await appState.signOut() }
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
