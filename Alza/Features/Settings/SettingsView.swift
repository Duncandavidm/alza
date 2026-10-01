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
                        DebtsView()
                    } label: {
                        Label("Deudas", systemImage: "creditcard.trianglebadge.exclamationmark")
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

                Section {
                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label("Seguridad", systemImage: "lock.shield.fill")
                    }
                }

                Section("Mi negocio") {
                    NavigationLink {
                        BusinessSettingsView()
                    } label: {
                        Label("Marca (logo, color, tipografia)", systemImage: "building.2.fill")
                    }

                    NavigationLink {
                        ProductsView()
                    } label: {
                        Label("Catalogo y precios", systemImage: "tag.fill")
                    }
                }

                Section("Suscripcion") {
                    switch appState.subscriptionStatus {
                    case .active(let expiresAt):
                        LabeledContent("Estado", value: "Activa")
                        let periodEndDate = appState.subscriptionStore.currentPeriodEndDate ?? expiresAt
                        if appState.subscriptionStore.willAutoRenew == false {
                            if let periodEndDate {
                                Text("Tu suscripcion no se va a renovar. Finaliza el \(periodEndDate.formatted(date: .long, time: .omitted)) — hasta esa fecha sigues con acceso completo.")
                                    .font(.footnote)
                                    .foregroundStyle(AlzaBrand.alert)
                            }
                        } else if let periodEndDate {
                            LabeledContent("Renueva", value: periodEndDate.formatted(date: .abbreviated, time: .omitted))
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
            .task {
                await appState.subscriptionStore.refreshRenewalInfo()
            }
        }
    }
}
