import Foundation
import UIKit
import AuthenticationServices
import Supabase

enum EmailAuthMode: Hashable {
    case signIn
    case signUp
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isSigningIn = false
    /// Muestra BrandLoadingView a pantalla completa encima del formulario
    /// mientras se inicia sesion (correo o Apple). Al entrar, RootView
    /// reemplaza AuthView por su propia pantalla de carga; si falla, se
    /// quita el overlay y se ve el error de siempre.
    @Published private(set) var showsSignInOverlay = false
    @Published private(set) var signInOverlayMessage = "Bienvenido"

    /// Tiempo minimo en pantalla del overlay para que no "parpadee".
    private static let minimumOverlayDuration: TimeInterval = 0.8
    private var overlayStartedAt: Date?

    @Published var emailAuthMode: EmailAuthMode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""

    private let supabase = SupabaseManager.shared.client
    private(set) var currentAppleNonce: String?

    var isEmailFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else { return false }

        if emailAuthMode == .signUp {
            return PasswordPolicy.isValid(password) && password == confirmPassword
        }
        // Al iniciar sesion no se le vuelve a exigir la politica actual a
        // una contraseña vieja que pudo crearse con una regla distinta —
        // solo que no este vacia. La politica real se aplica al crear o
        // cambiar la contraseña.
        return !password.isEmpty
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = CryptoNonce.random()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = CryptoNonce.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil

        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentAppleNonce
            else {
                errorMessage = "No se pudo leer la credencial de Apple."
                return
            }

            isSigningIn = true
            defer { isSigningIn = false }
            showSignInOverlay(message: "Bienvenido")

            do {
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                scheduleOverlayFallbackDismiss()
            } catch {
                await hideSignInOverlay()
                errorMessage = "No se pudo iniciar sesión con Apple: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Correo y contraseña

    func submitEmailForm() async {
        errorMessage = nil
        infoMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEmailFormValid else {
            if emailAuthMode == .signUp && !PasswordPolicy.isValid(password) {
                errorMessage = PasswordPolicy.failureReason(for: password)
            } else if emailAuthMode == .signUp && password != confirmPassword {
                errorMessage = "Las contraseñas no coinciden."
            } else {
                errorMessage = "Escribe un correo valido."
            }
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }
        showSignInOverlay(message: emailAuthMode == .signIn ? "Bienvenido" : "Creando tu cuenta…")

        do {
            switch emailAuthMode {
            case .signIn:
                _ = try await supabase.auth.signIn(email: trimmedEmail, password: password)
                scheduleOverlayFallbackDismiss()
            case .signUp:
                // Sin confirmacion de correo ("Confirm email" apagado en
                // Supabase): signUp ya trae la sesion y el usuario entra de
                // una (RootView reacciona a authStateChanges). El correo se
                // verifica con un codigo de 6 digitos solo antes del primer
                // canje (EmailVerificationSheet).
                let response = try await supabase.auth.signUp(email: trimmedEmail, password: password)
                if response.session == nil {
                    // Respaldo por si "Confirm email" sigue encendido: no
                    // hay sesion, se vuelve al formulario con el aviso.
                    await hideSignInOverlay()
                    infoMessage = "Te mandamos un correo a \(trimmedEmail) para confirmar tu cuenta. Confirma y vuelve a iniciar sesión."
                    emailAuthMode = .signIn
                    password = ""
                    confirmPassword = ""
                } else {
                    scheduleOverlayFallbackDismiss()
                }
            }
        } catch {
            await hideSignInOverlay()
            let detail = error.localizedDescription.lowercased()
            if detail.contains("weak") || detail.contains("pwned") || detail.contains("leaked") || detail.contains("easy to guess") {
                // Supabase rechazo una contraseña muy comun o filtrada.
                errorMessage = "Esa contraseña es muy común o apareció en filtraciones de otros sitios. Elige otra (por ejemplo, una frase con números)."
            } else {
                errorMessage = "No se pudo \(emailAuthMode == .signIn ? "iniciar sesion" : "crear la cuenta"): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Overlay de carga al iniciar sesion

    private func showSignInOverlay(message: String) {
        signInOverlayMessage = message
        overlayStartedAt = Date()
        showsSignInOverlay = true
    }

    /// Quita el overlay respetando el tiempo minimo en pantalla.
    private func hideSignInOverlay() async {
        guard showsSignInOverlay else { return }
        if let startedAt = overlayStartedAt {
            let remaining = Self.minimumOverlayDuration - Date().timeIntervalSince(startedAt)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        showsSignInOverlay = false
        overlayStartedAt = nil
    }

    /// Al iniciar sesion bien, RootView cambia a su propia pantalla de
    /// carga y AuthView desaparece con el overlay. Si por lo que sea la
    /// sesion no llega a RootView, no dejar al usuario atorado: quitar el
    /// overlay despues de unos segundos.
    private func scheduleOverlayFallbackDismiss() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.showsSignInOverlay = false
            self?.overlayStartedAt = nil
        }
    }
}
