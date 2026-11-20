import XCTest
@testable import MonAvi

/// Frecuencia de pago (1.0.2): mensual / semanal / diaria en recurrentes, y
/// quincenal en el onboarding como dos recurrentes mensuales.
final class RecurringFrequencyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func decode(_ extra: String) throws -> RecurringTransaction {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "user_id": "00000000-0000-0000-0000-000000000002",
          "account_id": "00000000-0000-0000-0000-000000000003",
          "name": "Salario",
          "amount": 500,
          "movement_type": "ingreso",
          "category": null,
          "day_of_month": 15,
          "active": true,
          "last_logged_on": null,
          "created_at": "2026-11-01T00:00:00Z",
          "updated_at": "2026-11-01T00:00:00Z"\(extra)
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecurringTransaction.self, from: Data(json.utf8))
    }

    // MARK: - Decodificacion

    func testRowWithoutFrequencyColumnIsMonthly() throws {
        let item = try decode("")
        XCTAssertEqual(item.frequency, .monthly)
        XCTAssertNil(item.weekday)
        XCTAssertEqual(item.scheduleDescription, "día 15")
    }

    func testUnknownFrequencyFallsBackToMonthly() throws {
        let item = try decode(#", "frequency": "yearly""#)
        XCTAssertEqual(item.frequency, .monthly)
    }

    func testWeeklyDecodes() throws {
        let item = try decode(#", "frequency": "weekly", "weekday": 6"#)
        XCTAssertEqual(item.frequency, .weekly)
        XCTAssertEqual(item.weekday, 6)
        XCTAssertEqual(item.scheduleDescription, "cada viernes")
    }

    // MARK: - isDueToday

    func testWeeklyDueOnItsWeekdayOnly() throws {
        let item = try decode(#", "frequency": "weekly", "weekday": 6"#)
        // 2026-11-20 es viernes; 2026-11-22 es domingo.
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2026, 11, 20)))
        XCTAssertFalse(item.isDueToday(calendar: calendar, today: date(2026, 11, 22)))
    }

    func testWeeklyLoggedThisWeekIsNotDue() throws {
        var item = try decode(#", "frequency": "weekly", "weekday": 6"#)
        item.lastLoggedOn = date(2026, 11, 20, hour: 8)
        XCTAssertFalse(item.isDueToday(calendar: calendar, today: date(2026, 11, 20)))
        // La semana siguiente vuelve a tocar.
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2026, 11, 27)))
    }

    func testDailyDueEveryDayUntilLoggedToday() throws {
        var item = try decode(#", "frequency": "daily""#)
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2026, 11, 22)))
        item.lastLoggedOn = date(2026, 11, 22, hour: 8)
        XCTAssertFalse(item.isDueToday(calendar: calendar, today: date(2026, 11, 22)))
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2026, 11, 23)))
    }

    func testMonthlyDay30IsDueOnLastDayOfFebruary() throws {
        let item = try decode("").withDay(30)
        // 2027-02-28 es el ultimo dia de febrero.
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2027, 2, 28)))
        XCTAssertFalse(item.isDueToday(calendar: calendar, today: date(2027, 2, 27)))
        XCTAssertTrue(item.isDueToday(calendar: calendar, today: date(2026, 11, 30)))
    }

    // MARK: - nextOccurrence(weekday:)

    func testNextWeekdayIsTodayWhenItMatches() {
        let next = NotificationManager.nextOccurrence(weekday: 6, now: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(next, calendar.startOfDay(for: date(2026, 11, 20)))
    }

    func testNextWeekdayLaterThisWeek() {
        // Domingo 22 → proximo viernes 27.
        let next = NotificationManager.nextOccurrence(weekday: 6, now: date(2026, 11, 22), calendar: calendar)
        XCTAssertEqual(next, calendar.startOfDay(for: date(2026, 11, 27)))
    }

    // MARK: - Onboarding

    @MainActor
    func testBiweeklyCreatesTwoMonthlyRowsSorted() {
        let viewModel = OnboardingViewModel()
        viewModel.fixedIncomeFrequency = .biweekly
        viewModel.fixedIncomeDay = 30 // el orden no importa
        viewModel.fixedIncomeSecondDay = 15
        let rows = viewModel.fixedIncomeRecurrences(userId: UUID(), accountId: UUID(), amount: 400)
        XCTAssertEqual(rows.map(\.dayOfMonth), [15, 30])
        XCTAssertEqual(rows.map(\.frequency), [.monthly, .monthly])
        XCTAssertEqual(rows.map(\.amount), [400, 400])
    }

    @MainActor
    func testBiweeklySameDayCollapsesToOne() {
        let viewModel = OnboardingViewModel()
        viewModel.fixedIncomeFrequency = .biweekly
        viewModel.fixedIncomeDay = 15
        viewModel.fixedIncomeSecondDay = 15
        let rows = viewModel.fixedIncomeRecurrences(userId: UUID(), accountId: UUID(), amount: 400)
        XCTAssertEqual(rows.count, 1)
    }

    @MainActor
    func testWeeklyAndDailyRows() {
        let viewModel = OnboardingViewModel()
        viewModel.fixedIncomeFrequency = .weekly
        viewModel.fixedIncomeWeekday = 6
        let weekly = viewModel.fixedIncomeRecurrences(userId: UUID(), accountId: UUID(), amount: 100)
        XCTAssertEqual(weekly.count, 1)
        XCTAssertEqual(weekly.first?.frequency, .weekly)
        XCTAssertEqual(weekly.first?.weekday, 6)

        viewModel.fixedIncomeFrequency = .daily
        let daily = viewModel.fixedIncomeRecurrences(userId: UUID(), accountId: UUID(), amount: 20)
        XCTAssertEqual(daily.first?.frequency, .daily)
        XCTAssertNil(daily.first?.weekday)
    }

    func testEncodingSendsWeekdayOnlyForWeekly() throws {
        let monthly = NewRecurringTransaction(
            userId: UUID(), accountId: UUID(), name: "x", amount: 1,
            movementType: .ingreso, category: nil, dayOfMonth: 1
        )
        let monthlyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(monthly)) as? [String: Any]
        XCTAssertEqual(monthlyJSON?["frequency"] as? String, "monthly")
        XCTAssertNil(monthlyJSON?["weekday"])

        let weekly = NewRecurringTransaction(
            userId: UUID(), accountId: UUID(), name: "x", amount: 1,
            movementType: .ingreso, category: nil, dayOfMonth: 1, frequency: .weekly, weekday: 3
        )
        let weeklyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(weekly)) as? [String: Any]
        XCTAssertEqual(weeklyJSON?["frequency"] as? String, "weekly")
        XCTAssertEqual(weeklyJSON?["weekday"] as? Int, 3)
    }
}

private extension RecurringTransaction {
    func withDay(_ day: Int) -> RecurringTransaction {
        var copy = self
        copy.dayOfMonth = day
        return copy
    }
}
