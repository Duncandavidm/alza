import XCTest
@testable import MonAvi

/// Preguntas por voz vs. movimientos para anotar.
final class VoiceQuestionDetectorTests: XCTestCase {
    func testQuestionsAreDetected() {
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("Cuánto gasté en súper este mes"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("¿Cuánto llevo gastado esta semana?"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("oye cuanto me queda del presupuesto de comida"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("En qué gasté más el mes pasado"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("Cómo voy este mes"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("a ver dime cuánto gané en octubre"))
        XCTAssertTrue(VoiceQuestionDetector.isQuestion("Qué gasté ayer"))
    }

    func testMovementsAreNotQuestions() {
        XCTAssertFalse(VoiceQuestionDetector.isQuestion("Gasté 12 dólares en almuerzo"))
        XCTAssertFalse(VoiceQuestionDetector.isQuestion("Me pagaron 500 de salario"))
        XCTAssertFalse(VoiceQuestionDetector.isQuestion("súper 45"))
        XCTAssertFalse(VoiceQuestionDetector.isQuestion(""))
    }

    func testWeakStartIsAMovementWhenItParses() {
        XCTAssertFalse(VoiceQuestionDetector.isQuestion("Que me pagaron 500 de salario"))
    }
}
