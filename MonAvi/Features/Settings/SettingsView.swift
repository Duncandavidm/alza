import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningOut = false
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    @AppStorage(NotificationManager.reminderLeadDaysKey) private var reminderLeadDays = NotificationManager.defaultLeadDays
    @AppStorage(NotificationManager.dailyLogReminderKey) private var dailyLogReminder = true
    @AppStorage(NotificationManager.dailyLogTimeKey) private var dailyLogMinutes = NotificationManager.defaultDailyLogMinutes
    @State private var testNotificationSent = false

    private var isNotificationAuthorized: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral
    }
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        Label("Mi perfil", systemImage: "person.crop.circle.fill")
                    }
                }

                Section("Preferencias") {
                    Toggle("Modo avanzado", isOn: $isAdvancedMode)
                    Text(isAdvancedMode
                        ? "Ves categoría y etiquetas al anotar un movimiento detallado."
                        : "Solo lo esencial al anotar: cuenta, tipo y monto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    notificationStatusRow

                    Stepper(
                        "Avisar \(reminderLeadDays) día\(reminderLeadDays == 1 ? "" : "s") antes",
                        value: $reminderLeadDays,
                        in: NotificationManager.leadDaysRange
                    )
                    .onChange(of: reminderLeadDays) { _, _ in
                        Task { await refreshReminders() }
                    }

                    Toggle("Recordarme anotar mis gastos", isOn: $dailyLogReminder)
                        .onChange(of: dailyLogReminder) { _, _ in
                            Task { await refreshReminders() }
                        }

                    if dailyLogReminder {
                        DatePicker(
                            "Hora del recordatorio",
                            selection: dailyLogTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: dailyLogMinutes) { _, _ in
                            Task { await refreshReminders() }
                        }
                    }

                    Button {
                        NotificationManager.sendTestNotification()
                        testNotificationSent = true
                        Task {
                            try? await Task.sleep(nanoseconds: 6_000_000_000)
                            testNotificationSent = false
                        }
                    } label: {
                        Label(
                            testNotificationSent ? "Llega en 5 segundos…" : "Probar sonido y vibración",
                            systemImage: "speaker.wave.2.fill"
                        )
                    }
                    .disabled(!isNotificationAuthorized)
                } header: {
                    Text("Notificaciones")
                } footer: {
                    Text("Te avisamos antes de que venza una cuenta por pagar o una factura, el día que vence y si se pasó. Para tus pagos fijos, unos días antes y el mismo día, para que no olvides registrarlos. También te decimos qué pagar primero cuando anotas un ingreso y, si quieres, te recordamos anotar tus gastos a la hora que elijas (solo si ese día no anotaste nada).")
                }

                Section {
                    NavigationLink {
                        DashboardView()
                    } label: {
                        Label("Cuentas", systemImage: "creditcard.fill")
                    }

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
                        PointsHubView()
                    } label: {
                        Label("Cashback", systemImage: "star.fill")
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

                /// Antes solo se veian estos enlaces en el paywall — alguien
                /// que ya es cliente Pro no vuelve a esa pantalla, asi que
                /// se quedaba sin forma de encontrarlos despues de suscribirse.
                Section("Legal y ayuda") {
                    Link(destination: Config.supportURL) {
                        Label("Ayuda y preguntas frecuentes", systemImage: "questionmark.circle.fill")
                    }
                    Link(destination: Config.privacyPolicyURL) {
                        Label("Política de privacidad", systemImage: "hand.raised.fill")
                    }
                    Link(destination: Config.termsOfUseURL) {
                        Label("Términos de uso", systemImage: "doc.text.fill")
                    }
                    if let mailURL = URL(string: "mailto:\(Config.supportEmail)") {
                        Link(destination: mailURL) {
                            Label("Escribenos", systemImage: "envelope.fill")
                        }
                    }
                }
                .foregroundStyle(.primary)

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

                    NavigationLink {
                        InvoicesView()
                    } label: {
                        Label("Facturas", systemImage: "doc.text.fill")
                    }
                }

                Section("Suscripción") {
                    switch appState.subscriptionStatus {
                    case .active(let expiresAt):
                        LabeledContent("Estado", value: "Activa")
                        let periodEndDate = appState.subscriptionStore.currentPeriodEndDate ?? expiresAt
                        if appState.subscriptionStore.willAutoRenew == false {
                            if let periodEndDate {
                                Text("Tu suscripción no se va a renovar. Finaliza el \(periodEndDate.formatted(date: .long, time: .omitted)) — hasta esa fecha sigues con acceso completo.")
                                    .font(.footnote)
                                    .foregroundStyle(MonAviBrand.alert)
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
                        LabeledContent("Estado", value: "Sin suscripción")
                    }

                    Button("Administrar suscripción") {
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
                            Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .disabled(isSigningOut)
                }

                Section {
                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Label("Eliminar cuenta", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
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
                .foregroundStyle(MonAviBrand.primary)
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
                    await refreshReminders()
                }
            } label: {
                Label("Activar notificaciones", systemImage: "bell.fill")
            }
        @unknown default:
            EmptyView()
        }
    }

    /// El DatePicker trabaja con fechas; aqui se guarda solo la hora del
    /// dia (minutos desde la medianoche).
    private var dailyLogTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = NotificationManager.clampedDailyLogMinutes(dailyLogMinutes)
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                dailyLogMinutes = (components.hour ?? 20) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func refreshReminders() async {
        guard let userId = appState.currentUserId else { return }
        await ReminderScheduler.refreshAll(userId: userId)
    }
}
