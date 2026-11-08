import XCTest
@testable import MonAvi

/// Logica pura de la verificacion del correo con codigo de 6 digitos.
final class EmailVerificationTests: XCTestCase {
    func testSanitizedCodeKeepsOnlySixDigits() {
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode(""), "")
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("123"), "123")
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("123 456"), "123456")
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("12-34-56"), "123456")
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("1234567890"), "123456")
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("ab1c2"), "12")
        // Digitos no ASCII (p. ej. arabigos) no cuentan.
        XCTAssertEqual(EmailVerificationLogic.sanitizedCode("١٢٣"), "")
    }

    func testIsComplete() {
        XCTAssertTrue(EmailVerificationLogic.isComplete("012345"))
        XCTAssertFalse(EmailVerificationLogic.isComplete("12345"))
        XCTAssertFalse(EmailVerificationLogic.isComplete("1234567"))
        XCTAssertFalse(EmailVerificationLogic.isComplete("12345a"))
    }

    func testResendTitleAndCooldownClock() {
        XCTAssertEqual(EmailVerificationLogic.resendTitle(remainingSeconds: 0), "Reenviar código")
        XCTAssertEqual(EmailVerificationLogic.resendTitle(remainingSeconds: -3), "Reenviar código")
        XCTAssertEqual(EmailVerificationLogic.resendTitle(remainingSeconds: 60), "Reenviar código en 1:00")
        XCTAssertEqual(EmailVerificationLogic.resendTitle(remainingSeconds: 45), "Reenviar código en 0:45")
        XCTAssertEqual(EmailVerificationLogic.cooldownClock(5), "0:05")
        XCTAssertEqual(EmailVerificationLogic.resendCooldownSeconds, 60)
    }

    func testExplanationIncludesEmail() {
        XCTAssertEqual(
            EmailVerificationLogic.explanation(email: "ana@correo.com"),
            "Para canjear premios, confirma tu correo. Te enviamos un código de 6 dígitos a ana@correo.com."
        )
        XCTAssertFalse(EmailVerificationLogic.explanation(email: nil).contains(" a ."))
    }

    func testIsVerificationRequired() {
        XCTAssertTrue(EmailVerificationLogic.isVerificationRequired(message: "Verifica tu correo para canjear"))
        XCTAssertTrue(EmailVerificationLogic.isVerificationRequired(message: "ERROR: verifica tu correo para canjear."))
        XCTAssertFalse(EmailVerificationLogic.isVerificationRequired(message: "No tienes puntos suficientes"))
    }

    func testVerifyErrorMessages() {
        XCTAssertEqual(
            EmailVerificationLogic.verifyErrorMessage(forErrorText: "Token has expired or is invalid otp_expired"),
            "El código es incorrecto o ya venció. Revísalo o pide uno nuevo."
        )
        XCTAssertEqual(
            EmailVerificationLogic.verifyErrorMessage(forErrorText: "Request rate limit reached over_request_rate_limit"),
            "Demasiados intentos. Espera unos minutos y vuelve a intentarlo."
        )
        XCTAssertEqual(
            EmailVerificationLogic.verifyErrorMessage(forErrorText: "Error Domain=NSURLErrorDomain Code=-1009"),
            "No hay conexión. Revisa tu internet e inténtalo de nuevo."
        )
        XCTAssertEqual(
            EmailVerificationLogic.verifyErrorMessage(forErrorText: "algo raro"),
            "No se pudo verificar el código. Inténtalo de nuevo."
        )
    }

    func testSendErrorMessages() {
        XCTAssertEqual(
            EmailVerificationLogic.sendErrorMessage(forErrorText: "For security purposes, you can only request this after 42 seconds."),
            "Ya te enviamos un código hace poco. Espera un momento antes de pedir otro."
        )
        XCTAssertEqual(
            EmailVerificationLogic.sendErrorMessage(forErrorText: "boom"),
            "No se pudo enviar el código. Inténtalo de nuevo en un momento."
        )
    }

    func testParseBool() {
        XCTAssertEqual(EmailVerificationLogic.parseBool(Data("true".utf8)), true)
        XCTAssertEqual(EmailVerificationLogic.parseBool(Data(" false\n".utf8)), false)
        XCTAssertEqual(EmailVerificationLogic.parseBool(Data("\"true\"".utf8)), true)
        XCTAssertNil(EmailVerificationLogic.parseBool(Data("null".utf8)))
    }
}
