import XCTest
@testable import MonAvi

/// Logica de "cerrar el dia" (mejora #5): clasifica el neto de hoy contra
/// el promedio de los dias anteriores. Es pura, asi que se puede fijar aqui.
@MainActor
final class DayJournalMoodTests: XCTestCase {
    private func mood(_ todayNet: Decimal, _ past: [Decimal]) -> DaySummary.Mood {
        DayJournalViewModel.mood(for: todayNet, comparedTo: past)
    }

    // Sin historial: solo importa si el dia cerro en positivo.
    func testNoHistoryPositiveIsNormal() {
        XCTAssertEqual(mood(50, []), .normal)
    }

    func testNoHistoryZeroOrNegativeIsSlow() {
        XCTAssertEqual(mood(0, []), .slow)
        XCTAssertEqual(mood(-20, []), .slow)
    }

    // Con historial: >10% sobre el promedio = buen dia.
    func testWellAboveAverageIsGood() {
        XCTAssertEqual(mood(200, [100, 100, 100]), .good)
    }

    // Dentro de ±10% del promedio = dia normal.
    func testAroundAverageIsNormal() {
        XCTAssertEqual(mood(100, [100, 100, 100]), .normal)
        XCTAssertEqual(mood(105, [100, 100, 100]), .normal)
    }

    // >10% por debajo del promedio = dia flojo.
    func testWellBelowAverageIsSlow() {
        XCTAssertEqual(mood(10, [100, 100, 100]), .slow)
    }

    // El promedio puede ser negativo (dias de puro gasto): un dia menos
    // malo que el promedio debe contar como bueno, no como flojo.
    func testBetterThanANegativeAverageIsGood() {
        XCTAssertEqual(mood(-50, [-100, -100, -100]), .good)
    }
}
