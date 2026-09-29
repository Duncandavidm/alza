import Foundation
import UIKit
import AuthenticationServices
import Supabase
import GoogleSignIn

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var isSigningIn = false

    private let supabase = SupabaseManager.shared.client
    private(set) var currentAppleNonce: String?

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

    // MARK: - Sign in with Google

    func signInWithGoogle(presenting viewController: UIViewController) async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google no regreso un id token."
                return
            }

            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken)
            )
        } catch {
            errorMessage = "No se pudo iniciar sesion con Google: \(error.localizedDescription)"
        }
    }
}
