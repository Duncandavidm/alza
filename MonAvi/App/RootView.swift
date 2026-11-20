import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var lock = BiometricLock.shared

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
        case loadFailed
    }

    private var screen: Screen {
        if appState.isLoadingSession { return .loading }
        if !appState.isSignedIn || appState.isHoldingAuthScreen { return .auth }
        if appState.mfaStatus == .unknown { return .loading }
        if appState.mfaStatus == .challengeRequired { return .mfaChallenge }
        if appState.onboardingStatus == .unknown { return .loading }
        if appState.onboardingStatus == .failed { return .loadFailed }
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
            case .loadFailed:
                StartupErrorView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: screen)
        .overlay {
            // Bloqueo con Face ID (Ajustes > Seguridad). Nunca encima de la
            // pantalla de error: "Cerrar sesión" tiene que quedar a mano.
            if lock.isEnabled && screen != .auth && screen != .loading && screen != .loadFailed {
                if lock.isLocked {
                    BiometricLockView(lock: lock, interactive: true)
                        .transition(.opacity)
                } else if scenePhase != .active {
                    BiometricLockView(lock: lock, interactive: false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            lock.handleScenePhase(phase)
        }
        .onChange(of: screen) { old, new in
            // Recien inicio sesion con su clave o Apple: no pedir Face ID encima.
            if old == .auth && new != .auth { lock.clearAfterSignIn() }
        }
    }
}

/// No se pudo terminar de cargar la cuenta al abrir la app (p. ej. sin
/// conexion). Antes esto dejaba la pantalla de carga para siempre, sin
/// ningun boton; ahora siempre hay salida.
private struct StartupErrorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isWorking = false

    var body: some View {
        ZStack {
            BrandLoadingView(message: "No pudimos cargar tu cuenta")

            VStack(spacing: 12) {
                Spacer()
                Text("Revisa tu conexión a internet e inténtalo de nuevo.")
                    .font(.footnote)
                    .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task {
                        isWorking = true
                        await appState.retryLoading()
                        isWorking = false
                    }
                } label: {
                    Text("Reintentar")
                        .font(.system(.headline, design: MonAviBrand.fontDesign))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(MonAviBrand.primary)

                Button("Cerrar sesión") {
                    Task {
                        isWorking = true
                        await appState.signOut()
                        isWorking = false
                    }
                }
                .font(.system(.subheadline, design: MonAviBrand.fontDesign))
                .foregroundStyle(MonAviBrand.onDarkSurface)
            }
            .disabled(isWorking)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
