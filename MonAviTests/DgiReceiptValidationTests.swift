import XCTest
@testable import MonAvi

final class DgiReceiptValidationTests: XCTestCase {
    private func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testHoyEsValido() {
        let now = Date()
        let result = DgiReceiptValidation.checkFreshness(fechaISO: iso(now), now: now, calendar: utcCalendar)
        XCTAssertEqual(result, .ok)
    }

    func testHaceTresDiasEsValido() {
        let now = Date()
        let threeDaysAgo = utcCalendar.date(byAdding: .day, value: -3, to: now)!
        let result = DgiReceiptValidation.checkFreshness(fechaISO: iso(threeDaysAgo), now: now, calendar: utcCalendar)
        XCTAssertEqual(result, .ok)
    }

    func testHaceCuatroDiasEsViejo() {
        let now = Date()
        let fourDaysAgo = utcCalendar.date(byAdding: .day, value: -4, to: now)!
        let result = DgiReceiptValidation.checkFreshness(fechaISO: iso(fourDaysAgo), now: now, calendar: utcCalendar)
        XCTAssertEqual(result, .tooOld)
    }

    func testFechaFuturaSeRechaza() {
        let now = Date()
        let tomorrow = utcCalendar.date(byAdding: .day, value: 1, to: now)!
        let result = DgiReceiptValidation.checkFreshness(fechaISO: iso(tomorrow), now: now, calendar: utcCalendar)
        XCTAssertEqual(result, .future)
    }

    func testFechaMalFormadaSeRechaza() {
        let result = DgiReceiptValidation.checkFreshness(fechaISO: "no-es-una-fecha", now: Date(), calendar: utcCalendar)
        XCTAssertEqual(result, .invalidDate)
    }
}
