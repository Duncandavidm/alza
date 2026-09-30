import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningOut = false
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false

    var body: some View {
        NavigationStack {
            List {
                Section("Preferencias") {
                    Toggle("Modo avanzado", isOn: $isAdvancedMode)
                    Text(isAdvancedMode
                        ? "Ves categoria y etiquetas al anotar un movimiento detallado."
                        : "Solo lo esencial al anotar: cuenta, tipo y monto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        BillsView()
                    } label: {
                        Label("Cuentas por pagar", systemImage: "tray.full.fill")
                    }

                    NavigationLink {
                        RecurringTransactionsView()
                    } label: {
                        Label("Recurrentes", systemImage: "arrow.trianglehead.2.clockwise")
                    }

                    NavigationLink {
                        DataPortabilityView()
                    } label: {
                        Label("Exportar / Importar CSV", systemImage: "arrow.up.arrow.down.circle")
                    }
                }

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
                    Button(role: .destructive) {
                        Task {
                            isSigningOut = true
                            await appState.signOut()
                            isSigningOut = false
                        }
                    } label: {
                        if isSigningOut {
                            ProgressView()
                        } else {
                            Text("Cerrar sesion")
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
