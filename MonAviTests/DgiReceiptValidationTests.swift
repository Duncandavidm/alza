import XCTest
@testable import MonAvi

final class DgiReceiptValidationTests: XCTestCase {
    private var panama: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }

    private func at(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = panama
        formatter.timeZone = panama.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func check(_ fecha: String, on now: String) -> DgiReceiptValidation.FreshnessResult {
        DgiReceiptValidation.checkFreshness(fechaISO: fecha, now: at(now), calendar: panama)
    }

    func testMismoDiaHastaTresDiasCashbackCompleto() {
        XCTAssertEqual(check("2026-08-20", on: "2026-08-20 10:00"), .ok(.full))
        XCTAssertEqual(check("2026-08-17", on: "2026-08-20 23:30"), .ok(.full))
    }

    func testDeCuatroASieteDiasMitad() {
        XCTAssertEqual(check("2026-08-16", on: "2026-08-20 00:30"), .ok(.half))
        XCTAssertEqual(check("2026-08-13", on: "2026-08-20 10:00"), .ok(.half))
    }

    func testMasDeSieteDiasDentroDelMesUnCuarto() {
        XCTAssertEqual(check("2026-08-12", on: "2026-08-20 10:00"), .ok(.quarter))
        XCTAssertEqual(check("2026-08-01", on: "2026-08-31 22:00"), .ok(.quarter))
    }

    func testMesAnteriorLosTresPrimerosDiasSinCashback() {
        XCTAssertEqual(check("2026-08-31", on: "2026-09-01 08:00"), .ok(.none))
        XCTAssertEqual(check("2026-08-05", on: "2026-09-03 23:30"), .ok(.none))
        // Enero acepta diciembre del año anterior.
        XCTAssertEqual(check("2025-12-28", on: "2026-01-02 09:00"), .ok(.none))
    }

    func testMesAnteriorDespuesDelDiaTresSeRechaza() {
        XCTAssertEqual(check("2026-08-31", on: "2026-09-04 00:30"), .tooOld)
    }

    func testDosMesesAtrasSeRechaza() {
        XCTAssertEqual(check("2026-07-31", on: "2026-09-01 08:00"), .tooOld)
    }

    func testFechaFuturaSeRechaza() {
        XCTAssertEqual(check("2026-08-21", on: "2026-08-20 23:30"), .future)
    }

    func testFechaMalFormadaSeRechaza() {
        XCTAssertEqual(check("no-es-una-fecha", on: "2026-08-20 10:00"), .invalidDate)
    }

    func testMultiplicadores() {
        XCTAssertEqual(DgiReceiptValidation.CashbackTier.full.multiplier, 1)
        XCTAssertEqual(DgiReceiptValidation.CashbackTier.half.multiplier, 0.5)
        XCTAssertEqual(DgiReceiptValidation.CashbackTier.quarter.multiplier, 0.25)
        XCTAssertEqual(DgiReceiptValidation.CashbackTier.none.multiplier, 0)
        XCTAssertNil(DgiReceiptValidation.tierMessage(.full))
        XCTAssertNotNil(DgiReceiptValidation.tierMessage(.none))
    }
}
