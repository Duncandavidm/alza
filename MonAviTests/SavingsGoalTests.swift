import XCTest
@testable import MonAvi

/// Propiedades calculadas de SavingsGoal — el "cuanto debo ahorrar al mes"
/// que pidio el cliente se recalcula siempre, no se guarda. Se fijan aqui
/// los casos que no dependen de la fecha de hoy, mas los limites (fecha
/// pasada, meta cumplida).
final class SavingsGoalTests: XCTestCase {
    private func goal(target: Decimal, current: Decimal, targetDate: String) -> SavingsGoal {
        SavingsGoal(
            id: UUID(),
            userId: UUID(),
            name: "Meta",
            emoji: "🎯",
            targetAmount: target,
            targetDate: targetDate,
            currentAmount: current,
            accountId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func testRemainingAmountClampsAtZero() {
        XCTAssertEqual(goal(target: 1000, current: 300, targetDate: "2099-01-01").remainingAmount, 700)
        XCTAssertEqual(goal(target: 1000, current: 1200, targetDate: "2099-01-01").remainingAmount, 0)
    }

    func testProgressIsClamped() {
        XCTAssertEqual(goal(target: 1000, current: 250, targetDate: "2099-01-01").progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(goal(target: 1000, current: 5000, targetDate: "2099-01-01").progress, 1)
        // Sin monto objetivo no se divide por cero.
        XCTAssertEqual(goal(target: 0, current: 100, targetDate: "2099-01-01").progress, 0)
    }

    func testIsAchieved() {
        XCTAssertTrue(goal(target: 1000, current: 1000, targetDate: "2099-01-01").isAchieved)
        XCTAssertFalse(goal(target: 1000, current: 999, targetDate: "2099-01-01").isAchieved)
    }

    // Meta cumplida: no pide aportar nada mas.
    func testAchievedNeedsNoContribution() {
        XCTAssertEqual(goal(target: 1000, current: 1000, targetDate: "2099-01-01").monthlyContributionNeeded, 0)
    }

    // Fecha ya vencida: monthsRemaining cae a 1, asi que la cuota sugerida
    // es todo lo que falta de una vez.
    func testPastDateAsksForFullRemaining() {
        let g = goal(target: 1000, current: 400, targetDate: "2020-01-01")
        XCTAssertEqual(g.monthsRemaining, 1)
        XCTAssertEqual(g.monthlyContributionNeeded, 600)
        XCTAssertTrue(g.isPastDue)
    }

    // monthsRemaining nunca baja de 1, y una fecha lejana reparte la cuota
    // (menor que todo lo que falta).
    func testFutureDateSpreadsContribution() {
        let g = goal(target: 1200, current: 0, targetDate: "2099-01-01")
        XCTAssertGreaterThanOrEqual(g.monthsRemaining, 1)
        XCTAssertGreaterThan(g.monthlyContributionNeeded, 0)
        XCTAssertLessThan(g.monthlyContributionNeeded, 1200)
    }
}
