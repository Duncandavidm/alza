import XCTest
@testable import MonAvi

final class NotificationManagerTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testOccurrenceLaterThisMonth() {
        let next = NotificationManager.nextOccurrence(dayOfMonth: 20, now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 20, hour: 0))
    }

    func testOccurrenceTodayCountsAsThisMonth() {
        let next = NotificationManager.nextOccurrence(dayOfMonth: 6, now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 6, hour: 0))
    }

    func testPassedDayMovesToNextMonth() {
        let next = NotificationManager.nextOccurrence(dayOfMonth: 2, now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(next, date(2026, 12, 2, hour: 0))
    }

    func testDay31InShortMonthFallsOnLastDay() {
        // Noviembre tiene 30 dias: "el 31" cae el 30, no el 1 de diciembre.
        let next = NotificationManager.nextOccurrence(dayOfMonth: 31, now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 30, hour: 0))

        // Febrero 2027 (28 dias), pedido despues del 31 de enero.
        let february = NotificationManager.nextOccurrence(dayOfMonth: 31, now: date(2027, 2, 1), calendar: calendar)
        XCTAssertEqual(february, date(2027, 2, 28, hour: 0))
    }

    /// iOS descarta en silencio los avisos locales que pasen de 64. El peor
    /// caso de lo que programamos a la vez debe quedar por debajo, con
    /// holgura para los avisos inmediatos (consejo de pago, sobrante). Este
    /// test evita que subir un tope (ej. maxBills) rompa el limite sin que
    /// nadie se de cuenta.
    func testWorstCaseStaysUnderSystemLimit() {
        XCTAssertEqual(NotificationManager.worstCaseScheduledCount, 59)
        XCTAssertLessThanOrEqual(NotificationManager.worstCaseScheduledCount, 60)
        XCTAssertLessThan(NotificationManager.worstCaseScheduledCount, 64)
    }

    func testDailyLogTimeClamp() {
        XCTAssertEqual(NotificationManager.clampedDailyLogMinutes(7 * 60 + 30), 450)
        XCTAssertEqual(NotificationManager.clampedDailyLogMinutes(0), 0)
        XCTAssertEqual(NotificationManager.clampedDailyLogMinutes(1439), 1439)
        XCTAssertEqual(NotificationManager.clampedDailyLogMinutes(1440), NotificationManager.defaultDailyLogMinutes)
        XCTAssertEqual(NotificationManager.clampedDailyLogMinutes(-5), NotificationManager.defaultDailyLogMinutes)
    }
}
