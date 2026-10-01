import Foundation

/// Regla de contraseña del lado del cliente: feedback inmediato en el
/// formulario. Esto NO reemplaza la politica del lado del servidor —
/// Supabase Auth tambien hay que configurarle un minimo de caracteres en
/// el dashboard (Authentication > Policies > Password), porque un check
/// solo en la app se puede saltar pegandole directo a la API. Las dos
/// cosas tienen que existir: cliente para UX, servidor para que de
/// verdad se cumpla.
enum PasswordPolicy {
    static let minimumLength = 8

    /// true si cumple el minimo aceptable para registrar/cambiar
    /// contraseña: largo + al menos una letra y un numero.
    static func isValid(_ password: String) -> Bool {
        guard password.count >= minimumLength else { return false }
        let hasLetter = password.contains { $0.isLetter }
        let hasNumber = password.contains { $0.isNumber }
        return hasLetter && hasNumber
    }

    /// Texto de ayuda a mostrar bajo el campo de contraseña.
    static let requirementsText = "Al menos \(minimumLength) caracteres, con letras y numeros."

    /// Mensaje de error especifico segun que le falta, para no dejar al
    /// usuario adivinando por que no puede continuar.
    static func failureReason(for password: String) -> String {
        if password.count < minimumLength {
            return "La contraseña debe tener al menos \(minimumLength) caracteres."
        }
        if !password.contains(where: { $0.isLetter }) {
            return "La contraseña debe incluir al menos una letra."
        }
        if !password.contains(where: { $0.isNumber }) {
            return "La contraseña debe incluir al menos un numero."
        }
        return "La contraseña no es valida."
    }
}
