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

    func testQuotaMessageFromServerIsShownAsIs() {
        let body = #"{"error": "Usaste tus 100 preguntas de este mes. Se renuevan el 1 de diciembre.", "code": "ai_quota"}"#
        let error = FunctionsError.httpError(code: 429, data: Data(body.utf8))
        XCTAssertEqual(message(error), "Usaste tus 100 preguntas de este mes. Se renuevan el 1 de diciembre.")
        XCTAssertEqual(AIErrorMessage.userMessage(from: error), "Usaste tus 100 preguntas de este mes. Se renuevan el 1 de diciembre.")
    }

    func testServerMessageOnlyFor429() {
        let body = #"{"error": "Internal"}"#
        XCTAssertNil(AIErrorMessage.userMessage(from: FunctionsError.httpError(code: 500, data: Data(body.utf8))))
        XCTAssertNil(AIErrorMessage.userMessage(from: FunctionsError.httpError(code: 429, data: Data("no json".utf8))))
    }

    func testAskQuotaCaption() {
        XCTAssertEqual(AIQuotaEntry(used: 3, limit: 100, remaining: 97, period: "month").askCaption,
                       "Te quedan 97 preguntas este mes")
        XCTAssertEqual(AIQuotaEntry(used: 99, limit: 100, remaining: 1, period: "month").askCaption,
                       "Te queda 1 pregunta este mes")
        XCTAssertEqual(AIQuotaEntry(used: 100, limit: 100, remaining: 0, period: "month").askCaption,
                       "Ya no te quedan preguntas este mes")
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
