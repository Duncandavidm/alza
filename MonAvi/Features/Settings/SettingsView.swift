import SwiftUI
import StoreKit
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSigningOut = false
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    /// Mismo valor que usa Hoy (DayJournalView) para ocultar "Tu ahorro".
    @AppStorage("monavi.hideSavingsCardInHoy") private var hideSavingsCardInHoy = false
    @AppStorage("monavi.hideBudgetInviteInHoy") private var hideBudgetInviteInHoy = false
    @AppStorage(NotificationManager.reminderLeadDaysKey) private var reminderLeadDays = NotificationManager.defaultLeadDays
    @AppStorage(NotificationManager.dailyLogReminderKey) private var dailyLogReminder = true
    @AppStorage(NotificationManager.dailyLogTimeKey) private var dailyLogMinutes = NotificationManager.defaultDailyLogMinutes
    @State private var testNotificationSent = false
    /// Idioma de la app (1.1.0): se aplica completo al volver a abrir MonAvi.
    @State private var language = AppLanguage.current
    @State private var isShowingLanguageNotice = false
    /// Hoja de App Store para canjear un codigo de oferta de suscripcion.
    @State private var isRedeemingOfferCode = false

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

                    NavigationLink {
                        ReferralView()
                    } label: {
                        Label("Invita amigos", systemImage: "gift.fill")
                    }
                }

                Section {
                    NavigationLink {
                        IncomeVerificationView()
                    } label: {
                        Label("Verificar ingresos", systemImage: "checkmark.seal")
                    }
                } footer: {
                    Text("Para el cashback, tus ingresos cuentan hasta $3,000 al mes sin verificar.")
                }

                Section("Preferencias") {
                    Picker(selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(verbatim: option.nativeName).tag(option)
                        }
                    } label: {
                        Label("Idioma", systemImage: "globe")
                    }
                    .onChange(of: language) { _, newValue in
                        guard newValue != AppLanguage.current else { return }
                        AppLanguage.choose(newValue)
                        Task { await appState.saveLanguagePreference(newValue) }
                        isShowingLanguageNotice = true
                    }
                    Toggle("Modo avanzado", isOn: $isAdvancedMode)
                    Text(isAdvancedMode
                        ? "Ves categoría y etiquetas al anotar un movimiento detallado."
                        : "Solo lo esencial al anotar: cuenta, tipo y monto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Mostrar «Tu ahorro» en Hoy", isOn: Binding(
                        get: { !hideSavingsCardInHoy },
                        set: { hideSavingsCardInHoy = !$0 }
                    ))
                    Toggle("Mostrar «Crea tu primer presupuesto»", isOn: Binding(
                        get: { !hideBudgetInviteInHoy },
                        set: { hideBudgetInviteInHoy = !$0 }
                    ))
                } header: {
                    Text("Pantalla Hoy")
                } footer: {
                    Text("Si los ocultaste con la X, aquí los vuelves a mostrar. Tus metas siguen en Ahorro y tus presupuestos en la pestaña Presupuestos (cuando creas uno, en Hoy aparecen las barras).")
                }

                Section {
                    NavigationLink {
                        BankAlertsGuideView()
                    } label: {
                        Label("Movimientos del banco, solos", systemImage: "bell.badge.fill")
                    }
                    NavigationLink {
                        VoiceBackTapGuideView()
                    } label: {
                        Label("Registra con doble toque", systemImage: "hand.tap.fill")
                    }
                    NavigationLink {
                        ControlCenterGuideView()
                    } label: {
                        Label("Botones del Centro de control", systemImage: "switch.2")
                    }
                    NavigationLink {
                        WalletAutomationGuideView()
                    } label: {
                        Label("Pagos con Apple Pay", systemImage: "wallet.pass.fill")
                    }
                } header: {
                    Text("Automatizaciones")
                } footer: {
                    Text("Que los avisos de tu banco o Yappy se conviertan en movimientos por confirmar, anotar con doble toque atrás (aun con la pantalla bloqueada) y registrar tus pagos con Apple Pay sin abrir la app.")
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
                        CategoriesView()
                    } label: {
                        Label("Categorías", systemImage: "square.grid.2x2.fill")
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
                }

                Section {
                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label("Seguridad", systemImage: "lock.shield.fill")
                    }
                }

                PrivacySettingsSection()

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

                Section("¿Te gusta MonAvi?") {
                    Link(destination: Config.appStoreReviewURL) {
                        Label("Califica MonAvi en la App Store", systemImage: "star.bubble.fill")
                    }
                    ShareLink(
                        item: Config.appStoreURL,
                        message: Text("Mira MonAvi, la app con la que ordeno mis finanzas y gano cashback con mis facturas:")
                    ) {
                        Label("Comparte MonAvi", systemImage: "square.and.arrow.up")
                    }
                }
                .foregroundStyle(.primary)

                Section("Suscripción") {
                    switch appState.subscriptionStatus {
                    case .active(let expiresAt):
                        LabeledContent("Estado", value: "Activa")
                        let periodEndDate = appState.subscriptionStore.currentPeriodEndDate ?? expiresAt
                        if appState.subscriptionStore.willAutoRenew == false {
                            if let periodEndDate {
                                Text("Tu suscripción no se va a renovar. Finaliza el \(periodEndDate.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: .monavi))) — hasta esa fecha sigues con acceso completo.")
                                    .font(.footnote)
                                    .foregroundStyle(MonAviBrand.alert)
                            }
                        } else if let periodEndDate {
                            LabeledContent("Renueva", value: periodEndDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))
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

                    Button("Canjear código") {
                        isRedeemingOfferCode = true
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
            .alert(Text(verbatim: language == .english ? "Language changed" : "Idioma cambiado"), isPresented: $isShowingLanguageNotice) {
                Button(role: .cancel) {} label: { Text(verbatim: "OK") }
            } message: {
                Text(verbatim: language == .english
                    ? "Close MonAvi and open it again to see the whole app in English."
                    : "Cierra MonAvi y vuelve a abrirla para ver toda la app en español.")
            }
            .offerCodeRedemption(isPresented: $isRedeemingOfferCode) { _ in
                Task {
                    await appState.subscriptionStore.syncCurrentEntitlements()
                    await appState.refreshSubscriptionStatus()
                }
            }
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
