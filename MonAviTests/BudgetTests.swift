import XCTest
@testable import MonAvi

/// Rango del periodo (decide que movimientos cuentan para "presupuesto
/// restante") y el semaforo de progreso — ambos puros.
final class BudgetTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")! // sin horario de verano
        calendar.firstWeekday = 2 // lunes
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMonthlyRangeIsCalendarMonth() {
        let (start, end) = BudgetPeriod.monthly.currentRange(containing: date(2026, 11, 15), calendar: calendar)
        XCTAssertEqual(start, date(2026, 11, 1, hour: 0))
        XCTAssertEqual(end, date(2026, 12, 1, hour: 0))
    }

    func testWeeklyRangeSpansSevenDaysAndContainsDate() {
        let d = date(2026, 11, 15)
        let (start, end) = BudgetPeriod.weekly.currentRange(containing: d, calendar: calendar)
        XCTAssertEqual(end.timeIntervalSince(start), 7 * 24 * 3600) // Panama no tiene DST
        XCTAssertLessThanOrEqual(start, d)
        XCTAssertLessThan(d, end)
        // El inicio cae a medianoche del primer dia de la semana (lunes).
        XCTAssertEqual(calendar.component(.weekday, from: start), 2)
    }

    private func progress(spent: Decimal, limit: Decimal) -> BudgetProgress {
        BudgetProgress(
            budget: Budget(
                id: UUID(), userId: UUID(), category: "Comida",
                period: .monthly, limitAmount: limit, color: nil,
                createdAt: Date(), updatedAt: Date()
            ),
            spent: spent
        )
    }

    func testRatioAndZeroLimit() {
        XCTAssertEqual(progress(spent: 50, limit: 200).ratio, 0.25, accuracy: 0.0001)
        XCTAssertEqual(progress(spent: 10, limit: 0).ratio, 0) // no se divide por cero
    }

    func testStatusThresholds() {
        XCTAssertEqual(progress(spent: 50, limit: 200).status, .onTrack)   // 0.25
        XCTAssertEqual(progress(spent: 160, limit: 200).status, .warning)  // 0.80
        XCTAssertEqual(progress(spent: 199, limit: 200).status, .warning)  // 0.995
        XCTAssertEqual(progress(spent: 200, limit: 200).status, .over)     // 1.0
        XCTAssertEqual(progress(spent: 250, limit: 200).status, .over)     // 1.25
    }
}
