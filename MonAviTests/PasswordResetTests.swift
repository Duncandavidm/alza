import XCTest
@testable import MonAvi

/// Logica pura del cambio de contraseña con codigo (PasswordResetSheet)
/// y de la politica de contraseña que usa.
final class PasswordResetTests: XCTestCase {
    func testPasswordPolicy() {
        XCTAssertTrue(PasswordPolicy.isValid("abcdefg1"))
        XCTAssertFalse(PasswordPolicy.isValid("abc1"))
        XCTAssertFalse(PasswordPolicy.isValid("abcdefgh"))
        XCTAssertFalse(PasswordPolicy.isValid("12345678"))
        XCTAssertEqual(
            PasswordPolicy.failureReason(for: "abc1"),
            "La contraseña debe tener al menos 8 caracteres."
        )
    }

    func testNewPasswordError() {
        XCTAssertNil(PasswordResetLogic.newPasswordError(password: "nueva1234", confirmation: "nueva1234"))
        XCTAssertEqual(
            PasswordResetLogic.newPasswordError(password: "corta1", confirmation: "corta1"),
            "La contraseña debe tener al menos 8 caracteres."
        )
        XCTAssertEqual(
            PasswordResetLogic.newPasswordError(password: "nueva1234", confirmation: "nueva12345"),
            "Las contraseñas no coinciden."
        )
        XCTAssertEqual(
            PasswordResetLogic.newPasswordError(password: "sololetras", confirmation: "sololetras"),
            "La contraseña debe incluir al menos un numero."
        )
    }

    func testCanSubmit() {
        XCTAssertTrue(PasswordResetLogic.canSubmit(
            code: "123456", codeAlreadyVerified: false, password: "nueva1234", confirmation: "nueva1234"
        ))
        XCTAssertFalse(PasswordResetLogic.canSubmit(
            code: "12345", codeAlreadyVerified: false, password: "nueva1234", confirmation: "nueva1234"
        ))
        // Codigo ya verificado (reintento tras un rechazo del servidor).
        XCTAssertTrue(PasswordResetLogic.canSubmit(
            code: "", codeAlreadyVerified: true, password: "nueva1234", confirmation: "nueva1234"
        ))
        XCTAssertFalse(PasswordResetLogic.canSubmit(
            code: "123456", codeAlreadyVerified: false, password: "nueva1234", confirmation: "otra1234"
        ))
    }

    func testEmailValidation() {
        XCTAssertTrue(PasswordResetLogic.isPlausibleEmail("ana@correo.com"))
        XCTAssertTrue(PasswordResetLogic.isPlausibleEmail("  ana@correo.com \n"))
        XCTAssertFalse(PasswordResetLogic.isPlausibleEmail(""))
        XCTAssertFalse(PasswordResetLogic.isPlausibleEmail("ana"))
        XCTAssertFalse(PasswordResetLogic.isPlausibleEmail("@correo.com"))
        XCTAssertFalse(PasswordResetLogic.isPlausibleEmail("ana@"))
        XCTAssertFalse(PasswordResetLogic.isPlausibleEmail("ana maria@correo.com"))
        XCTAssertEqual(PasswordResetLogic.trimmedEmail(" ana@correo.com "), "ana@correo.com")
    }

    func testCodeSentMessageNeverConfirmsAccount() {
        XCTAssertEqual(
            PasswordResetLogic.codeSentMessage(email: "ana@correo.com"),
            "Si el correo está registrado, te enviamos un código de 6 dígitos a ana@correo.com."
        )
    }

    func testUpdateErrorMessages() {
        XCTAssertEqual(
            PasswordResetLogic.updateErrorMessage(forErrorText: "New password should be different from the old password. same_password"),
            "La nueva contraseña debe ser distinta a la anterior."
        )
        XCTAssertEqual(
            PasswordResetLogic.updateErrorMessage(forErrorText: "Password should be at least 8 characters. weak_password"),
            "La contraseña es muy débil. Usa al menos 8 caracteres, con letras y números."
        )
        XCTAssertEqual(
            PasswordResetLogic.updateErrorMessage(forErrorText: "AAL2 session is required insufficient_aal"),
            "Tu cuenta tiene verificación en 2 pasos. Escribe el código de tu app de autenticación."
        )
        XCTAssertEqual(
            PasswordResetLogic.updateErrorMessage(forErrorText: "Error Domain=NSURLErrorDomain Code=-1009"),
            "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        )
        XCTAssertEqual(
            PasswordResetLogic.updateErrorMessage(forErrorText: "something else"),
            "No se pudo cambiar la contraseña. Inténtalo de nuevo."
        )
    }
}
