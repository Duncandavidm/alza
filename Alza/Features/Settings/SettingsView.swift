import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningOut = false
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    @AppStorage(NotificationManager.reminderLeadDaysKey) private var reminderLeadDays = NotificationManager.defaultLeadDays
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

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
                    notificationStatusRow

                    Stepper(
                        "Avisar \(reminderLeadDays) dia\(reminderLeadDays == 1 ? "" : "s") antes",
                        value: $reminderLeadDays,
                        in: NotificationManager.leadDaysRange
                    )
                } header: {
                    Text("Notificaciones")
                } footer: {
                    Text("Te avisamos cuando una cuenta por pagar o una factura esta por vencer (y el dia que vence), cuando te toca un pago fijo del mes, y que pagar primero cada vez que anotas un ingreso.")
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
                        SavingsGoalsView()
                    } label: {
                        Label("Metas de ahorro", systemImage: "target")
                    }

                    NavigationLink {
                        DataPortabilityView()
                    } label: {
                        Label("Exportar / Importar CSV", systemImage: "arrow.up.arrow.down.circle")
                    }

                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("Sugerencias", systemImage: "lightbulb")
                    }

                    NavigationLink {
                        FamilyGroupView()
                    } label: {
                        Label("Mi familia", systemImage: "person.2.fill")
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
                                    .foregroundStyle(AmadaiBrand.alert)
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
                            Label("Cerrar sesion", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("Ajustes")
            .task {
                await appState.subscriptionStore.refreshRenewalInfo()
            }
            .task {
                notificationStatus = await NotificationManager.authorizationStatus()
            }
        }
    }

    @ViewBuilder
    private var notificationStatusRow: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Notificaciones activadas", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AmadaiBrand.primary)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Activar en Ajustes de iOS", systemImage: "bell.slash.fill")
            }
        case .notDetermined:
            Button {
                Task {
                    await NotificationManager.requestAuthorization()
                    notificationStatus = await NotificationManager.authorizationStatus()
                }
            } label: {
                Label("Activar notificaciones", systemImage: "bell.fill")
            }
        @unknown default:
            EmptyView()
        }
    }
}
