import Foundation
import Supabase
import StoreKit

enum OnboardingStatus: Equatable {
    case unknown
    case pending
    case completed
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
    @Published private(set) var onboardingStatus: OnboardingStatus = .unknown
    @Published private(set) var mfaStatus: MFAChallengeStatus = .unknown

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
                self.session = state.session
                self.isLoadingSession = false

                if state.session != nil {
                    await self.refreshMFAStatus()
                    await self.refreshSubscriptionStatus()
                    await self.refreshOnboardingStatus()
                    await self.subscriptionStore.loadProduct()
                } else {
                    self.subscriptionStatus = .none
                    self.onboardingStatus = .unknown
                    self.mfaStatus = .unknown
                }
            }
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    func refreshSubscriptionStatus() async {
        guard let userId = session?.user.id else {
            subscriptionStatus = .none
            return
        }
        do {
            let row: SubscriptionRow? = try await supabase
                .from("subscriptions")
                .select()
                .eq("user_id", value: userId)
                .maybeSingle()
                .execute()
                .value
            subscriptionStatus = SubscriptionStatus(row: row)
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
        struct Row: Decodable {
            let onboardingCompletedAt: Date?
            enum CodingKeys: String, CodingKey { case onboardingCompletedAt = "onboarding_completed_at" }
        }
        do {
            let row: Row = try await supabase
                .from("profiles")
                .select("onboarding_completed_at")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            onboardingStatus = row.onboardingCompletedAt != nil ? .completed : .pending
        } catch {
            onboardingStatus = .unknown
        }
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
