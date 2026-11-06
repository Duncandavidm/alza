import XCTest
import Supabase
@testable import MonAvi

/// El cliente nunca debe ver "Edge Function returned a non-2xx status code".
/// Se fija que cada tipo de error de IA se traduzca a lenguaje normal.
@MainActor
final class AIErrorTests: XCTestCase {
    private func message(_ error: Error) -> String {
        InsightsViewModel.friendlyAIError(error, action: "responder tu pregunta")
    }

    func testTooManyRequests() {
        let msg = message(FunctionsError.httpError(code: 429, data: Data()))
        XCTAssertTrue(msg.contains("muchas consultas"))
        XCTAssertFalse(msg.lowercased().contains("non-2xx"))
    }

    func testServerErrorIsFriendly() {
        for code in [500, 502, 503] {
            let msg = message(FunctionsError.httpError(code: code, data: Data()))
            XCTAssertTrue(msg.contains("no está disponible"), "code \(code)")
            XCTAssertFalse(msg.contains("status code"))
        }
    }

    func testClientErrorFallsBackToGenericMessage() {
        // Un 400 no tiene mensaje propio: cae al generico, nunca al tecnico.
        let msg = message(FunctionsError.httpError(code: 400, data: Data()))
        XCTAssertEqual(msg, "No se pudo responder tu pregunta. Intenta de nuevo más tarde.")
    }

    func testNoConnection() {
        let msg = message(URLError(.notConnectedToInternet))
        XCTAssertTrue(msg.contains("conexión"))
    }

    func testUnknownErrorIsGeneric() {
        struct Weird: Error {}
        XCTAssertEqual(message(Weird()), "No se pudo responder tu pregunta. Intenta de nuevo más tarde.")
    }
}
