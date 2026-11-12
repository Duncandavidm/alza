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

    /// En Panama (UTC-5) una factura de hace exactamente 3 dias calendario
    /// se acepta, y una de hace 4 no — sin importar la hora del dia.
    func testPanamaTimeZoneAcceptsThreeFullDays() {
        var panama = Calendar(identifier: .gregorian)
        panama.timeZone = TimeZone(identifier: "America/Panama")!
        let formatter = DateFormatter()
        formatter.calendar = panama
        formatter.timeZone = panama.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lateNight = formatter.date(from: "2026-11-13 23:30")!
        let earlyMorning = formatter.date(from: "2026-11-13 00:30")!

        for now in [lateNight, earlyMorning] {
            XCTAssertEqual(DgiReceiptValidation.checkFreshness(fechaISO: "2026-11-10", now: now, calendar: panama), .ok)
            XCTAssertEqual(DgiReceiptValidation.checkFreshness(fechaISO: "2026-11-13", now: now, calendar: panama), .ok)
            XCTAssertEqual(DgiReceiptValidation.checkFreshness(fechaISO: "2026-11-09", now: now, calendar: panama), .tooOld)
            XCTAssertEqual(DgiReceiptValidation.checkFreshness(fechaISO: "2026-11-14", now: now, calendar: panama), .future)
        }
    }
}
