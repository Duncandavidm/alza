import Foundation
import UIKit
import AuthenticationServices
import Supabase

enum EmailAuthMode {
    case signIn
    case signUp
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isSigningIn = false

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

            do {
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
            } catch {
                errorMessage = "No se pudo iniciar sesion con Apple: \(error.localizedDescription)"
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

        do {
            switch emailAuthMode {
            case .signIn:
                _ = try await supabase.auth.signIn(email: trimmedEmail, password: password)
            case .signUp:
                let response = try await supabase.auth.signUp(email: trimmedEmail, password: password)
                if response.session == nil {
                    infoMessage = "Te mandamos un correo a \(trimmedEmail) para confirmar tu cuenta. Confirma y vuelve a iniciar sesion."
                    emailAuthMode = .signIn
                    password = ""
                    confirmPassword = ""
                }
            }
        } catch {
            errorMessage = "No se pudo \(emailAuthMode == .signIn ? "iniciar sesion" : "crear la cuenta"): \(error.localizedDescription)"
        }
    }

    func sendPasswordReset() async {
        errorMessage = nil
        infoMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            errorMessage = "Escribe tu correo arriba para poder enviarte el link de recuperacion."
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await supabase.auth.resetPasswordForEmail(trimmedEmail)
            infoMessage = "Te mandamos un correo a \(trimmedEmail) con un link para restablecer tu contraseña."
        } catch {
            errorMessage = "No se pudo enviar el correo de recuperacion: \(error.localizedDescription)"
        }
    }
}
