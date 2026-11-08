import Foundation

/// Logica pura del cambio de contraseña con codigo de 6 digitos
/// (PasswordResetSheet). Sin dependencias de red para poder probarla.
/// El codigo, la espera para reenviar y los errores de envio/verificacion
/// se comparten con EmailVerificationLogic.
enum PasswordResetLogic {
    static func trimmedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validacion minima del correo antes de pedir el codigo.
    static func isPlausibleEmail(_ email: String) -> Bool {
        let trimmed = trimmedEmail(email)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !local.isEmpty && !domain.isEmpty && !trimmed.contains(" ")
    }

    /// Texto del paso 2. Nunca confirma si el correo existe.
    static func codeSentMessage(email: String) -> String {
        "Si el correo está registrado, te enviamos un código de 6 dígitos a \(email)."
    }

    static let mismatchMessage = "Las contraseñas no coinciden."

    /// nil si la nueva contraseña cumple la politica (PasswordPolicy) y
    /// coincide con la confirmacion; si no, el mensaje a mostrar.
    static func newPasswordError(password: String, confirmation: String) -> String? {
        if !PasswordPolicy.isValid(password) {
            return PasswordPolicy.failureReason(for: password)
        }
        if password != confirmation {
            return mismatchMessage
        }
        return nil
    }

    /// true si se puede intentar el cambio: codigo completo (o ya
    /// verificado antes) y contraseña valida que coincide.
    static func canSubmit(code: String, codeAlreadyVerified: Bool, password: String, confirmation: String) -> Bool {
        (codeAlreadyVerified || EmailVerificationLogic.isComplete(code))
            && newPasswordError(password: password, confirmation: confirmation) == nil
    }

    /// Error al guardar la nueva contraseña (`update(user:)`), a partir
    /// del texto del error de Supabase Auth.
    static func updateErrorMessage(forErrorText text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("same_password") || lower.contains("different from the old") {
            return "La nueva contraseña debe ser distinta a la anterior."
        }
        if lower.contains("weak_password") || lower.contains("password should")
            || lower.contains("weak password") {
            return "La contraseña es muy débil. Usa al menos \(PasswordPolicy.minimumLength) caracteres, con letras y números."
        }
        if lower.contains("insufficient_aal") || lower.contains("aal2") {
            return "Tu cuenta tiene verificación en 2 pasos. Escribe el código de tu app de autenticación."
        }
        if lower.contains("rate limit") || lower.contains("rate_limit") || lower.contains("too many") {
            return "Demasiados intentos. Espera unos minutos y vuelve a intentarlo."
        }
        if lower.contains("nsurlerrordomain") || lower.contains("offline")
            || lower.contains("network connection") || lower.contains("internet") {
            return "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        }
        return "No se pudo cambiar la contraseña. Inténtalo de nuevo."
    }
}
