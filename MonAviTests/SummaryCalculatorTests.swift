import XCTest
@testable import MonAvi

final class SummaryCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let accountA = UUID()
    private let accountB = UUID()
    private let userId = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func transaction(
        _ amount: Decimal,
        _ type: MovementType,
        category: String?,
        on date: Date,
        account: UUID? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            userId: userId,
            accountId: account ?? accountA,
            amount: type.signedAmount(from: amount),
            movementType: type,
            category: category,
            description: nil,
            tags: [],
            originalCurrency: nil,
            originalAmount: nil,
            occurredAt: date,
            createdAt: date
        )
    }

    private var calculator: SummaryCalculator {
        SummaryCalculator(calendar: calendar, now: date(2026, 11, 15))
    }

    func testMonthIntervalAndPrevious() {
        let current = calculator.interval(for: .month, offset: 0)
        XCTAssertEqual(current.start, date(2026, 11, 1, hour: 0))
        XCTAssertEqual(current.end, date(2026, 12, 1, hour: 0))

        let previous = calculator.interval(for: .month, offset: -1)
        XCTAssertEqual(previous.start, date(2026, 10, 1, hour: 0))
        XCTAssertEqual(previous.end, current.start)
    }

    func testMonthHasOneBucketPerDay() {
        let interval = calculator.interval(for: .month, offset: 0)
        XCTAssertEqual(calculator.bucketIntervals(for: .month, in: interval).count, 30)
    }

    func testQuarterAndLastSixMonths() {
        let quarter = calculator.interval(for: .quarter, offset: 0)
        XCTAssertEqual(quarter.start, date(2026, 10, 1, hour: 0))
        XCTAssertEqual(quarter.end, date(2027, 1, 1, hour: 0))

        let sixMonths = calculator.interval(for: .last6Months, offset: 0)
        XCTAssertEqual(sixMonths.start, date(2026, 6, 1, hour: 0))
        XCTAssertEqual(sixMonths.end, date(2026, 12, 1, hour: 0))
        XCTAssertEqual(calculator.bucketIntervals(for: .last6Months, in: sixMonths).count, 6)
    }

    func testYearToDateComparesSameSpan() {
        let current = calculator.interval(for: .yearToDate, offset: 0)
        let previous = calculator.interval(for: .yearToDate, offset: -1)
        XCTAssertEqual(current.start, date(2026, 1, 1, hour: 0))
        XCTAssertEqual(previous.start, date(2025, 1, 1, hour: 0))
        XCTAssertEqual(current.duration, previous.duration, accuracy: 3600 * 25)
    }

    func testSnapshotTotalsCategoriesAndDelta() {
        let transactions = [
            transaction(100, .gasto, category: "Vivienda", on: date(2026, 11, 2)),
            transaction(50, .gasto, category: "Comida", on: date(2026, 11, 3)),
            transaction(25, .gasto, category: "Comida", on: date(2026, 11, 3)),
            transaction(30, .pagoProveedor, category: nil, on: date(2026, 11, 4)),
            transaction(500, .ingreso, category: nil, on: date(2026, 11, 5)),
            transaction(999, .transferencia, category: nil, on: date(2026, 11, 5)),
            transaction(205, .gasto, category: "Comida", on: date(2026, 10, 10)),
        ]

        let snapshot = calculator.snapshot(
            transactions: transactions,
            kind: .expenses,
            period: .month,
            offset: 0,
            accountId: nil
        )

        XCTAssertEqual(snapshot.total, 205)
        XCTAssertEqual(snapshot.previousTotal, 205)
        XCTAssertEqual(snapshot.deltaPercent, 0)
        XCTAssertEqual(snapshot.transactions.count, 4)

        XCTAssertEqual(snapshot.categories.map(\.key), ["Vivienda", "Comida", SummaryCalculator.uncategorizedKey])
        let food = snapshot.categories.first { $0.key == "Comida" }
        XCTAssertEqual(food?.count, 2)
        XCTAssertEqual(food?.total, 75)
        XCTAssertEqual(food?.previousTotal, 205)

        // 15 dias transcurridos (1-15 nov) -> 205 / 15
        XCTAssertEqual(snapshot.averagePerBucket, Decimal(205) / Decimal(15))
        XCTAssertEqual(snapshot.buckets.first { $0.label == "3" }?.total, 75)
    }

    func testIncomeAndAccountFilter() {
        let transactions = [
            transaction(500, .ingreso, category: nil, on: date(2026, 11, 5), account: accountA),
            transaction(300, .ingreso, category: "Ingreso", on: date(2026, 11, 6), account: accountB),
            transaction(80, .gasto, category: "Comida", on: date(2026, 11, 6), account: accountB),
        ]

        let all = calculator.snapshot(transactions: transactions, kind: .income, period: .month, offset: 0, accountId: nil)
        XCTAssertEqual(all.total, 800)
        XCTAssertEqual(all.categories.map(\.key), ["Ingreso"])

        let onlyB = calculator.snapshot(transactions: transactions, kind: .income, period: .month, offset: 0, accountId: accountB)
        XCTAssertEqual(onlyB.total, 300)
    }

    func testMidnightOfFirstDayBelongsToNewMonth() {
        let transactions = [transaction(10, .gasto, category: "Comida", on: date(2026, 11, 1, hour: 0))]
        let november = calculator.snapshot(transactions: transactions, kind: .expenses, period: .month, offset: 0, accountId: nil)
        let october = calculator.snapshot(transactions: transactions, kind: .expenses, period: .month, offset: -1, accountId: nil)
        XCTAssertEqual(november.total, 10)
        XCTAssertEqual(october.total, 0)
    }

    func testKeypadRules() {
        XCTAssertEqual(AmountKeypad.applying(.digit(5), to: ""), "5")
        XCTAssertEqual(AmountKeypad.applying(.digit(5), to: "0"), "5")
        XCTAssertEqual(AmountKeypad.applying(.dot, to: ""), "0.")
        XCTAssertEqual(AmountKeypad.applying(.dot, to: "12.5"), "12.5")
        XCTAssertEqual(AmountKeypad.applying(.digit(9), to: "12.50"), "12.50")
        XCTAssertEqual(AmountKeypad.applying(.digit(9), to: "123456789"), "123456789")
        XCTAssertEqual(AmountKeypad.applying(.delete, to: "12."), "12")
        XCTAssertEqual(AmountKeypad.applying(.delete, to: ""), "")
    }
}
