import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    /// Que pantalla toca mostrar. Todos los estados de "todavia no se
    /// sabe" caen en `.loading`, asi la misma BrandLoadingView se queda
    /// en pantalla (sin reiniciar su animacion) mientras se resuelven
    /// sesion -> MFA -> suscripcion -> onboarding.
    private enum Screen: Hashable {
        case loading
        case auth
        case mfaChallenge
        case onboarding
        case paywall
        case dashboard
    }

    private var screen: Screen {
        if appState.isLoadingSession { return .loading }
        if !appState.isSignedIn || appState.isHoldingAuthScreen { return .auth }
        if appState.mfaStatus == .unknown { return .loading }
        if appState.mfaStatus == .challengeRequired { return .mfaChallenge }
        if appState.onboardingStatus == .unknown { return .loading }
        if appState.onboardingStatus == .pending { return .onboarding }
        // Mientras se esta consultando la suscripcion (y todavia no hay
        // un estado conocido) no se muestra el paywall, para que no
        // "parpadee" antes del dashboard. Si la consulta falla, el estado
        // queda en .unknown pero ya sin consulta en curso -> paywall como
        // antes.
        if appState.subscriptionStatus == .unknown && appState.isCheckingSubscription { return .loading }
        if !appState.subscriptionStatus.isEntitled { return .paywall }
        return .dashboard
    }

    var body: some View {
        ZStack {
            switch screen {
            case .loading:
                BrandLoadingView()
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .mfaChallenge:
                MFAChallengeView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .paywall:
                PaywallView(subscriptionStore: appState.subscriptionStore)
                    .transition(.opacity)
            case .dashboard:
                DashboardTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: screen)
    }
}
