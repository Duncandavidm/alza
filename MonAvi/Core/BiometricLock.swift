import SwiftUI
import LocalAuthentication

/// Bloqueo de la app con Face ID / Touch ID (o el código del iPhone si la
/// biometría falla). Es opcional: se activa en Ajustes > Seguridad.
/// - Al abrir la app con sesión iniciada, pide desbloquear.
/// - Al volver a la app desde otra app o la pantalla de inicio, también.
/// - Mientras la app no está activa (selector de apps), tapa el contenido.
@MainActor
final class BiometricLock: ObservableObject {
    static let shared = BiometricLock()

    private static let enabledKey = "monavi.biometricLock.enabled"
    private static let graceSeconds: TimeInterval = 0

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    private var backgroundedAt: Date?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    enum Kind { case faceID, touchID, opticID, passcode, none }

    /// Qué puede usar este iPhone.
    static var availableKind: Kind {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcode
            }
        }
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcode : .none
    }

    static var methodName: String {
        switch availableKind {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcode: return "el código del iPhone"
        case .none: return "Face ID"
        }
    }

    static var systemImage: String {
        switch availableKind {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .passcode: return "lock.fill"
        default: return "faceid"
        }
    }

    /// Activa o desactiva. Para activar pide autenticar primero.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            guard await authenticate(reason: "Activa el desbloqueo de MonAvi") else { return false }
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
        return true
    }

    /// La persona acaba de iniciar sesión: no se le pide desbloquear.
    func clearAfterSignIn() {
        isLocked = false
        backgroundedAt = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "Desbloquea MonAvi") {
            isLocked = false
        }
    }

    /// Llamar desde RootView con cada cambio de scenePhase.
    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled else { return }
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            if let since = backgroundedAt, Date().timeIntervalSince(since) >= Self.graceSeconds {
                isLocked = true
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Pantalla de bloqueo (y tapa del selector de apps).
struct BiometricLockView: View {
    @ObservedObject var lock: BiometricLock
    /// false: solo tapa el contenido (app inactiva), sin pedir Face ID.
    let interactive: Bool

    var body: some View {
        ZStack {
            MonAviBrand.primary.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                EmbeddedLogo.monAviMarkWhite
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("MonAvi")
                    .font(.system(.title, design: MonAviBrand.fontDesign, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if interactive {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Desbloquear con \(BiometricLock.methodName)", systemImage: BiometricLock.systemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(MonAviBrand.primary)
                    .disabled(lock.isAuthenticating)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .task {
            if interactive { await lock.unlock() }
        }
    }
}
