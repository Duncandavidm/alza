import XCTest
@testable import MonAvi

/// 1.0.4: ahorro bloqueado hasta una fecha ("disponible en diciembre").
final class SavingsAvailabilityTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func account(balance: Decimal, availableOn: String?) -> Account {
        Account(
            id: UUID(), userId: UUID(), name: "Ahorros", type: .savings, balance: balance, currency: "USD",
            createdAt: Date(), updatedAt: Date(), debtId: nil, availableOn: availableOn
        )
    }

    func testNoLockIsAlwaysAvailableAndNeverAsks() {
        let free = account(balance: 3000, availableOn: nil)
        XCTAssertFalse(SavingsAvailability.isLocked(free, now: date(2026, 11, 21), calendar: calendar))
        XCTAssertFalse(SavingsAvailability.isDue(free, now: date(2026, 12, 1), calendar: calendar))
    }

    func testLockedUntilDecemberThenDue() {
        let locked = account(balance: 3000, availableOn: "2026-12-01")
        XCTAssertTrue(SavingsAvailability.isLocked(locked, now: date(2026, 11, 21), calendar: calendar))
        XCTAssertFalse(SavingsAvailability.isDue(locked, now: date(2026, 11, 30), calendar: calendar))
        // El mismo dia (a cualquier hora) y despues: se pregunta.
        XCTAssertTrue(SavingsAvailability.isDue(locked, now: date(2026, 12, 1, hour: 7), calendar: calendar))
        XCTAssertFalse(SavingsAvailability.isLocked(locked, now: date(2026, 12, 1, hour: 7), calendar: calendar))
        XCTAssertTrue(SavingsAvailability.isDue(locked, now: date(2026, 12, 15), calendar: calendar))
    }

    func testEmptyAccountDoesNotAsk() {
        let empty = account(balance: 0, availableOn: "2026-12-01")
        XCTAssertFalse(SavingsAvailability.isDue(empty, now: date(2026, 12, 2), calendar: calendar))
    }

    func testDateRoundTripAndSuggestion() {
        let parsed = SavingsAvailability.date(from: "2026-12-01", calendar: calendar)!
        XCTAssertEqual(SavingsAvailability.string(from: parsed, calendar: calendar), "2026-12-01")
        let suggestion = SavingsAvailability.suggestedDate(now: date(2026, 11, 21), calendar: calendar)
        XCTAssertEqual(SavingsAvailability.string(from: suggestion, calendar: calendar), "2026-12-01")
        let nextYear = SavingsAvailability.suggestedDate(now: date(2026, 12, 20), calendar: calendar)
        XCTAssertEqual(SavingsAvailability.string(from: nextYear, calendar: calendar), "2027-12-01")
    }
}
