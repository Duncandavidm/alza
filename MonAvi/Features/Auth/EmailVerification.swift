import Foundation
import Supabase

/// Logica pura de la verificacion del correo con codigo de 6 digitos
/// (antes del primer canje). Sin dependencias de red para poder probarla.
enum EmailVerificationLogic {
    /// Largo del codigo que manda Supabase (`{{ .Token }}` en la plantilla).
    static let codeLength = 6
    /// Espera entre envios del codigo (Supabase tambien limita a 1 por
    /// minuto por correo).
    static let resendCooldownSeconds = 60
    /// Texto exacto con el que la RPC `redeem_reward` rechaza el canje
    /// cuando el correo no esta verificado.
    static let verificationRequiredMessage = "Verifica tu correo para canjear"

    /// Deja solo digitos (tambien los que pega o autocompleta iOS con
    /// espacios o guiones) y como maximo 6.
    static func sanitizedCode(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(codeLength))
    }

    static func isComplete(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Titulo del boton de reenviar: con la cuenta regresiva mientras dura
    /// la espera.
    static func resendTitle(remainingSeconds: Int) -> String {
        guard remainingSeconds > 0 else { return "Reenviar código" }
        return "Reenviar código en \(cooldownClock(remainingSeconds))"
    }

    /// 60 -> "1:00", 45 -> "0:45", 5 -> "0:05".
    static func cooldownClock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func explanation(email: String?) -> String {
        guard let email, !email.isEmpty else {
            return "Para canjear premios, confirma tu correo. Te enviamos un código de 6 dígitos."
        }
        return "Para canjear premios, confirma tu correo. Te enviamos un código de 6 dígitos a \(email)."
    }

    /// true si el mensaje de error del canje es el de "falta verificar el
    /// correo".
    static func isVerificationRequired(message: String) -> Bool {
        message.range(of: verificationRequiredMessage, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Mensajes de error

    /// Error al verificar el codigo, a partir del texto del error de
    /// Supabase Auth (mensaje y/o codigo, p. ej. "Token has expired or is
    /// invalid" / `otp_expired`, `over_request_rate_limit`).
    static func verifyErrorMessage(forErrorText text: String) -> String {
        let lower = text.lowercased()
        if isRateLimit(lower) {
            return "Demasiados intentos. Espera unos minutos y vuelve a intentarlo."
        }
        if isNetwork(lower) {
            return "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        }
        if lower.contains("expired") || lower.contains("otp_expired") {
            return "El código es incorrecto o ya venció. Revísalo o pide uno nuevo."
        }
        if lower.contains("invalid") || lower.contains("token") || lower.contains("otp") {
            return "El código no es correcto. Revísalo o pide uno nuevo."
        }
        return "No se pudo verificar el código. Inténtalo de nuevo."
    }

    /// Error al enviar (o reenviar) el codigo.
    static func sendErrorMessage(forErrorText text: String) -> String {
        let lower = text.lowercased()
        if isRateLimit(lower) {
            return "Ya te enviamos un código hace poco. Espera un momento antes de pedir otro."
        }
        if isNetwork(lower) {
            return "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        }
        return "No se pudo enviar el código. Inténtalo de nuevo en un momento."
    }

    private static func isRateLimit(_ lower: String) -> Bool {
        lower.contains("rate limit") || lower.contains("rate_limit")
            || lower.contains("too many") || lower.contains("429")
            || lower.contains("security purposes")
    }

    private static func isNetwork(_ lower: String) -> Bool {
        lower.contains("nsurlerrordomain") || lower.contains("offline")
            || lower.contains("network connection") || lower.contains("internet")
    }

    /// Lee el booleano que devuelve una RPC escalar de PostgREST (`true` /
    /// `false`, a veces entre comillas o con espacios).
    static func parseBool(_ data: Data) -> Bool? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .lowercased()
        switch text {
        case "true", "t": return true
        case "false", "f": return false
        default: return nil
        }
    }

    /// Texto para clasificar un error: el mensaje localizado mas la
    /// descripcion completa (que incluye el codigo de error de Auth).
    static func errorText(_ error: Error) -> String {
        "\(error.localizedDescription) \(String(describing: error))"
    }
}

enum EmailVerificationError: Error {
    case notMarked
}

/// Llamadas a Supabase para verificar el correo con un codigo de 6
/// digitos. El servidor (RPC `mark_email_verified`) solo acepta marcarlo
/// si el JWT actual vino de verificar un codigo (amr = otp).
@MainActor
final class EmailVerificationService {
    static let shared = EmailVerificationService()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    /// Correo del usuario de la sesion actual.
    func currentEmail() async -> String? {
        guard let email = try? await supabase.auth.session.user.email?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty else { return nil }
        return email
    }

    /// Manda el codigo (plantilla de Supabase con `{{ .Token }}`). No crea
    /// usuarios nuevos.
    func sendCode(to email: String) async throws {
        try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: false)
    }

    /// Verifica el codigo (esto renueva la sesion con amr = otp) y luego
    /// marca el correo como verificado del lado del servidor.
    func verify(email: String, code: String) async throws {
        _ = try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
        let response = try await supabase
            .rpc("mark_email_verified")
            .execute()
        if EmailVerificationLogic.parseBool(response.data) == false {
            throw EmailVerificationError.notMarked
        }
    }

    private struct IsVerifiedParams: Encodable {
        let pUserId: UUID
        enum CodingKeys: String, CodingKey { case pUserId = "p_user_id" }
    }

    func isVerified(userId: UUID) async throws -> Bool {
        let response = try await supabase
            .rpc("email_is_verified", params: IsVerifiedParams(pUserId: userId))
            .execute()
        return EmailVerificationLogic.parseBool(response.data) ?? false
    }
}
