import Foundation
import Supabase
import StoreKit
import WidgetKit

enum OnboardingStatus: Equatable {
    case unknown
    case pending
    case completed
    /// No se pudo leer el perfil (p. ej. sin conexión). RootView muestra
    /// "Reintentar" / "Cerrar sesión" en vez de quedarse cargando.
    case failed
}

enum MFAChallengeStatus: Equatable {
    case unknown
    /// El usuario no tiene verificacion en 2 pasos activa, o ya la
    /// completo en esta sesion.
    case satisfied
    /// Tiene un factor TOTP verificado pero la sesion actual todavia esta
    /// en AAL1 — hay que resolver el challenge antes de dejarlo entrar.
    case challengeRequired
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoadingSession = true
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .unknown
    /// true mientras refreshSubscriptionStatus() esta consultando. RootView
    /// lo usa para mostrar la pantalla de carga (en vez del paywall)
    /// mientras el estado todavia es .unknown.
    @Published private(set) var isCheckingSubscription = false
    /// product_id de la suscripcion que da el acceso actual (mensual o
    /// anual). nil si no hay ninguna.
    @Published private(set) var entitlementProductId: String?
    /// Suscripcion en prueba gratis: los descuentos, bonos y canjes se ven
    /// en gris y se desbloquean al empezar el plan pagado (0096/0097).
    @Published private(set) var isInFreeTrial = false
    private var didRegisterDevice = false
    @Published private(set) var onboardingStatus: OnboardingStatus = .unknown
    @Published private(set) var mfaStatus: MFAChallengeStatus = .unknown
    /// true mientras PasswordResetSheet esta abierta: verifyOTP(.recovery)
    /// crea la sesion antes de guardar la nueva contraseña, y RootView
    /// tiene que seguir mostrando AuthView (con la hoja encima) hasta que
    /// termine o se cancele.
    @Published private(set) var isHoldingAuthScreen = false
    /// Pais y moneda de la cuenta (profiles.country). Al cambiar, RootView
    /// redibuja la app para que los montos salgan en la moneda nueva.
    @Published private(set) var country: AppCountry = AppCountry.current
    /// Hay más de un país para elegir (Colombia activada desde el panel).
    /// Si no, el registro no muestra la elección de país.
    @Published private(set) var offersCountryChoice: Bool = AppCountry.available.count > 1

    let subscriptionStore = SubscriptionStore()
    private let supabase = SupabaseManager.shared.client
    private var authTask: Task<Void, Never>?

    var isSignedIn: Bool { session != nil }
    var currentUserId: UUID? { session?.user.id }

    func start() {
        subscriptionStore.onVerifiedTransaction = { [weak self] transaction in
            await self?.reportTransaction(transaction)
        }
        subscriptionStore.start()

        authTask = Task {
            for await state in supabase.auth.authStateChanges {
                var currentSession = state.session
                if state.event == .initialSession, let stored = currentSession, stored.isExpired {
                    // La sesion guardada llego vencida: se renueva antes de
                    // entrar. Si no se puede renovar (refresh token invalido),
                    // el SDK emite signedOut y el siguiente evento la limpia;
                    // sin conexion se sigue con la guardada, como antes.
                    currentSession = (try? await supabase.auth.session) ?? stored
                }
                self.session = currentSession
                self.isLoadingSession = false

                if state.session != nil {
                    await self.refreshMFAStatus()
                    await self.refreshSubscriptionStatus()
                    await self.refreshOnboardingStatus()
                    await self.subscriptionStore.loadProduct()
                    await UserCategoriesStore.shared.refresh()
                } else {
                    UserCategoriesStore.shared.clear()
                    self.subscriptionStatus = .none
                    self.onboardingStatus = .unknown
                    self.mfaStatus = .unknown
                }
            }
        }
    }

    func setHoldingAuthScreen(_ hold: Bool) {
        isHoldingAuthScreen = hold
    }

    func signOut() async {
        // Antes de cerrar la sesion (la RLS pide al dueno): que este
        // dispositivo deje de recibir push de esta cuenta.
        await PushTokenService.shared.removeCurrentToken()
        try? await supabase.auth.signOut()
        // Si el cierre global falla (p. ej. la cuenta ya no existe en el
        // servidor), la sesion no puede quedarse en el Keychain: sobrevive
        // a reinstalar la app y dejaria el arranque trabado.
        if supabase.auth.currentSession != nil {
            try? await supabase.auth.signOut(scope: .local)
        }
        clearLocalAccountData()
    }

    /// Cambia el pais (y la moneda) en este iPhone: montos, widgets y
    /// cuentas nuevas. No convierte montos.
    func applyCountry(_ newCountry: AppCountry) {
        AppCountry.current = newCountry
        if country != newCountry {
            country = newCountry
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Lo que la cuenta deja guardado en este iPhone fuera de la sesion:
    /// los widgets ("Tu día", presupuestos) y los movimientos detectados
    /// por confirmar. Se borra al cerrar sesion o eliminar la cuenta.
    private func clearLocalAccountData() {
        AppCountry.reset()
        country = AppCountry.current
        DayWidgetSnapshot.clear()
        BudgetWidgetSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
        DetectedMovementStore.shared.clearAll()
    }

    /// La sesion guardada pertenece a una cuenta que ya no existe (borrada
    /// desde el panel mientras este telefono tenia la sesion abierta). Se
    /// descarta solo en este dispositivo y se vuelve a la pantalla de
    /// inicio de sesion.
    private func discardDeadSession() async {
        try? await supabase.auth.signOut(scope: .local)
        clearLocalAccountData()
        session = nil
        onboardingStatus = .unknown
        mfaStatus = .unknown
        subscriptionStatus = .none
        entitlementProductId = nil
        isInFreeTrial = false
    }

    /// "Reintentar" de la pantalla de error de arranque.
    func retryLoading() async {
        onboardingStatus = .unknown
        await refreshMFAStatus()
        await refreshSubscriptionStatus()
        await refreshOnboardingStatus()
    }

    /// Apple exige (Guideline 5.1.1(v)) poder eliminar la cuenta desde
    /// dentro de la app. Llama a la Edge Function delete-account (borra
    /// auth.users del lado del servidor con la service role key — todas
    /// las tablas con datos del usuario tienen
    /// `on delete cascade`, ver el comentario de esa funcion) y, si sale
    /// bien, limpia la sesion local igual que signOut().
    func deleteAccount() async throws {
        guard let userId = currentUserId else { return }
        struct Payload: Encodable { let userId: String }
        _ = try await supabase.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(body: Payload(userId: userId.uuidString))
        )
        await signOut()
    }

    /// Lee el acceso efectivo del usuario (su propia suscripcion) via la
    /// RPC get_entitlement_status en vez de leer directo la tabla
    /// subscriptions.
    func refreshSubscriptionStatus() async {
        guard session?.user.id != nil else {
            subscriptionStatus = .none
            entitlementProductId = nil
            isInFreeTrial = false
            return
        }
        isCheckingSubscription = true
        defer { isCheckingSubscription = false }
        do {
            let rows: [EntitlementRow] = try await supabase
                .rpc("get_entitlement_status")
                .execute()
                .value
            if let row = rows.first {
                subscriptionStatus = SubscriptionStatus(status: row.status, expiresAt: row.expiresAt)
                entitlementProductId = row.productId
                isInFreeTrial = row.isTrial && subscriptionStatus.isEntitled
            } else {
                subscriptionStatus = .none
                entitlementProductId = nil
                isInFreeTrial = false
            }
        } catch {
            subscriptionStatus = .unknown
        }
    }

    /// Le pregunta a Supabase si la sesion actual necesita (y todavia no
    /// completo) el segundo paso de verificacion. Se llama al entrar y
    /// otra vez cuando MFAChallengeView resuelve el codigo.
    func refreshMFAStatus() async {
        guard session != nil else {
            mfaStatus = .unknown
            return
        }
        mfaStatus = await MFAService.isChallengeRequired() ? .challengeRequired : .satisfied
    }

    func refreshOnboardingStatus() async {
        guard let userId = session?.user.id else {
            onboardingStatus = .unknown
            return
        }
        await refreshAppFlags()
        struct Row: Decodable {
            let onboardingCompletedAt: Date?
            let country: String?
            let language: String?
            enum CodingKeys: String, CodingKey {
                case onboardingCompletedAt = "onboarding_completed_at"
                case country
                case language
            }
        }
        do {
            // Lista en vez de .single(): cero filas no es un error de red,
            // es la señal de que la cuenta ya no existe (el perfil se crea
            // con la cuenta por trigger y se borra en cascada con ella).
            let rows: [Row] = try await supabase
                .from("profiles")
                .select("onboarding_completed_at, country, language")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                await discardDeadSession()
                return
            }
            if let saved = row.country.flatMap(AppCountry.init(rawValue:)), row.onboardingCompletedAt != nil {
                applyCountry(saved)
            }
            onboardingStatus = row.onboardingCompletedAt != nil ? .completed : .pending
            // Revisión de muchas cuentas en el mismo iPhone (0100).
            if !didRegisterDevice {
                didRegisterDevice = true
                let userId = currentUserId
                Task {
                    await IncomeVerificationService.registerDevice()
                    // DeviceCheck de Apple (0103).
                    if let userId { await DeviceCheckService.checkIfDue(userId: userId) }
                }
            }
            // La IA, los avisos y los correos hablan en el idioma de la app.
            if row.language != AppLanguage.current.rawValue {
                await saveLanguagePreference(AppLanguage.current)
            }
        } catch {
            onboardingStatus = .failed
        }
    }

    /// Guarda el idioma en el perfil (profiles.language, 0098): la IA, las
    /// notificaciones del servidor y los correos responden en ese idioma.
    func saveLanguagePreference(_ language: AppLanguage) async {
        guard let userId = session?.user.id else { return }
        struct Update: Encodable { let language: String }
        _ = try? await supabase
            .from("profiles")
            .update(Update(language: language.rawValue))
            .eq("id", value: userId)
            .execute()
        // También en los datos del usuario de Auth: las plantillas de correo
        // (códigos de verificación y de contraseña) eligen el idioma con él.
        _ = try? await supabase.auth.update(user: UserAttributes(data: ["language": .string(language.rawValue)]))
    }

    /// Banderas que se prenden desde el panel (por ahora, Colombia). Si
    /// falla la consulta se queda con lo último que se supo.
    func refreshAppFlags() async {
        struct Flags: Decodable {
            let colombiaEnabled: Bool?
            enum CodingKeys: String, CodingKey { case colombiaEnabled = "colombia_enabled" }
        }
        do {
            let flags: Flags = try await supabase.rpc("get_app_flags").execute().value
            AppCountry.colombiaEnabled = flags.colombiaEnabled ?? false
        } catch {
            // sin red: se mantiene el valor guardado
        }
        offersCountryChoice = AppCountry.available.count > 1
    }

    /// Se llama justo al terminar el wizard, para no tener que esperar un
    /// round trip antes de dejar entrar al usuario al dashboard.
    func markOnboardingCompleted() {
        onboardingStatus = .completed
    }

    /// Manda la transaccion verificada por StoreKit a la Edge Function
    /// verify-apple-receipt (unico lugar con permiso para escribir en
    /// public.subscriptions), y luego relee el estado desde la base.
    private func reportTransaction(_ transaction: Transaction) async {
        guard let userId = session?.user.id else { return }

        struct Payload: Encodable {
            let userId: String
            let originalTransactionId: String
        }

        do {
            _ = try await supabase.functions.invoke(
                "verify-apple-receipt",
                options: FunctionInvokeOptions(
                    body: Payload(
                        userId: userId.uuidString,
                        originalTransactionId: String(transaction.originalID)
                    )
                )
            )
            await refreshSubscriptionStatus()
            await subscriptionStore.refreshRenewalInfo()
        } catch {
            // Se reintentara en el proximo refreshSubscriptionStatus() /
            // en el proximo lanzamiento via Transaction.currentEntitlements.
        }
    }
}
