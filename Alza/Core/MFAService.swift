import Foundation
import Supabase

/// Envoltorio fino sobre supabase.auth.mfa — verificacion de 2 pasos
/// (TOTP: Google Authenticator, Authy, 1Password, etc.) usando la API de
/// MFA que ya trae Supabase Auth. Nada de esto se guarda en nuestra base;
/// Supabase es quien guarda el factor (secreto TOTP) del lado del
/// servidor, y la app solo pide/verifica codigos.
enum MFAService {
    private static var supabase: SupabaseClient { SupabaseManager.shared.client }

    struct EnrollResult {
        let factorId: String
        /// otpauth://... — se usa para generar el QR nativo (CoreImage) y
        /// tambien sirve de respaldo si el usuario quiere copiarlo.
        let uri: String
        /// El secreto en texto, para quien prefiera escribirlo a mano en
        /// su app de autenticacion en vez de escanear el QR.
        let secret: String
    }

    /// Empieza el enrolamiento de un nuevo factor TOTP. El factor NO queda
    /// activo todavia — hay que confirmarlo con `verify(factorId:code:)`
    /// una vez el usuario escanee el QR y escriba el codigo de 6 digitos
    /// que le muestre su app de autenticacion.
    static func enrollTOTP() async throws -> EnrollResult {
        let response = try await supabase.auth.mfa.enroll(
            params: MFATotpEnrollParams(issuer: "Avi")
        )
        guard let totp = response.totp else {
            throw MFAServiceError.missingTOTPPayload
        }
        return EnrollResult(factorId: response.id, uri: totp.uri, secret: totp.secret)
    }

    /// Confirma el enrolamiento (o resuelve un challenge de login) con el
    /// codigo de 6 digitos. challengeAndVerify hace el challenge + verify
    /// en un solo paso.
    static func verify(factorId: String, code: String) async throws {
        _ = try await supabase.auth.mfa.challengeAndVerify(
            params: MFAChallengeAndVerifyParams(factorId: factorId, code: code)
        )
    }

    static func unenroll(factorId: String) async throws {
        _ = try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factorId))
    }

    static func listVerifiedFactors() async throws -> [Factor] {
        let response = try await supabase.auth.mfa.listFactors()
        return response.totp.filter { $0.status == .verified }
    }

    /// true si el usuario tiene un factor TOTP verificado pero la sesion
    /// actual todavia esta en AAL1 (solo password/Apple/Google, sin el
    /// segundo paso) — osea, le falta completar el challenge para entrar.
    static func isChallengeRequired() async -> Bool {
        guard
            let levels = try? await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
        else { return false }
        return levels.currentLevel != "aal2" && levels.nextLevel == "aal2"
    }
}

enum MFAServiceError: Error {
    case missingTOTPPayload
}
