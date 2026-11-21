import XCTest
@testable import MonAvi

/// 1.0.4: "Tu foto financiera" (fin del onboarding y Análisis), montos
/// escritos a mano y deteccion de gastos que se repiten cada mes.
final class FinancialSnapshotTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Foto financiera

    func testHealthyProfileIsGood() {
        let snapshot = FinancialSnapshot(
            monthlyIncome: 2000, fixedExpenses: 700, debts: [], cash: 1500, savings: 1000
        )
        XCTAssertEqual(snapshot.freeMoney, 1300)
        XCTAssertEqual(snapshot.fixedShare ?? 0, 0.35, accuracy: 0.001)
        XCTAssertEqual(snapshot.health, .good)
        XCTAssertFalse(snapshot.plan.isEmpty)
        XCTAssertLessThanOrEqual(snapshot.plan.count, 3)
    }

    func testCreditUtilizationAndPlan() {
        let card = FinancialSnapshot.DebtInput(name: "Tarjeta", balance: 1600, creditLimit: 2000, minimumPayment: 80)
        let snapshot = FinancialSnapshot(monthlyIncome: 1500, fixedExpenses: 650, debts: [card], cash: 300, savings: 0)
        XCTAssertEqual(snapshot.creditUtilization ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.health, .attention)
        XCTAssertTrue(snapshot.plan.contains { $0.text.contains("Baja Tarjeta a menos de $600") })
        XCTAssertTrue(snapshot.observations.contains { $0.text.contains("usas el 80%") })
    }

    func testOverdueDebtComesFirstInPlan() {
        let loan = FinancialSnapshot.DebtInput(name: "Préstamo", balance: 900, minimumPayment: 120, isOverdue: true)
        let snapshot = FinancialSnapshot(monthlyIncome: 1200, fixedExpenses: 400, debts: [loan], cash: 100, savings: 0)
        XCTAssertEqual(snapshot.health, .attention)
        XCTAssertTrue(snapshot.plan.first?.text.contains("Ponte al día con Préstamo") ?? false)
    }

    func testMissingMinimumIsEstimatedAtThreePercent() {
        let card = FinancialSnapshot.DebtInput(name: "Visa", balance: 1000)
        XCTAssertEqual(FinancialSnapshot.minimum(for: card), 30)
    }

    func testCommitmentsAboveIncome() {
        let snapshot = FinancialSnapshot(monthlyIncome: 800, fixedExpenses: 950, debts: [], cash: 0, savings: 0)
        XCTAssertEqual(snapshot.freeMoney, -150)
        XCTAssertEqual(snapshot.health, .attention)
        XCTAssertTrue(snapshot.plan.contains { $0.text.contains("Recorta $150") })
    }

    func testNoIncomeStillGivesObservations() {
        let snapshot = FinancialSnapshot(monthlyIncome: 0, fixedExpenses: 300, debts: [], cash: 0, savings: 0)
        XCTAssertNil(snapshot.fixedShare)
        XCTAssertTrue(snapshot.observations.contains { $0.text.contains("No anotaste un ingreso fijo") })
    }

    func testMoneyFormat() {
        XCTAssertEqual(FinancialSnapshot.money(1600), "$1,600")
        XCTAssertEqual(FinancialSnapshot.money(Decimal(string: "52.3")!), "$52.30")
    }

    func testOnboardingMonthlyIncomeByFrequency() async {
        await MainActor.run {
            let viewModel = OnboardingViewModel()
            viewModel.hasFixedIncome = true
            viewModel.fixedIncomeAmountText = "500"
            viewModel.fixedIncomeFrequency = .biweekly
            viewModel.fixedIncomeDay = 15
            viewModel.fixedIncomeSecondDay = 30
            XCTAssertEqual(viewModel.monthlyFixedIncome, 1000)
            viewModel.fixedIncomeFrequency = .monthly
            XCTAssertEqual(viewModel.monthlyFixedIncome, 500)
            viewModel.commonBills[0].isEnabled = true
            viewModel.commonBills[0].amountText = "50"
            XCTAssertEqual(viewModel.monthlyFixedExpenses, 50)
        }
    }

    // MARK: - Montos escritos

    func testAmountParser() {
        XCTAssertEqual(RecurringAmountParser.parse("52,30"), Decimal(string: "52.30"))
        XCTAssertEqual(RecurringAmountParser.parse("$52.30"), Decimal(string: "52.30"))
        XCTAssertEqual(RecurringAmountParser.parse(" 1,250.50 "), Decimal(string: "1250.50"))
        XCTAssertEqual(RecurringAmountParser.parse("1.250,50"), Decimal(string: "1250.50"))
        XCTAssertEqual(RecurringAmountParser.parse("1,250"), 1250)
        XCTAssertEqual(RecurringAmountParser.parse("48"), 48)
        XCTAssertNil(RecurringAmountParser.parse("cincuenta"))
        XCTAssertNil(RecurringAmountParser.parse("0"))
        XCTAssertNil(RecurringAmountParser.parse(""))
    }

    // MARK: - Gastos que se repiten

    private let account = UUID()

    private func entry(_ text: String, _ amount: Decimal, _ when: Date) -> RecurringDetector.Entry {
        RecurringDetector.Entry(description: text, amount: amount, date: when, accountId: account, category: "housing")
    }

    func testDetectsSameExpenseTwoMonthsInARow() {
        let entries = [entry("Luz", 48, date(2026, 10, 12)), entry("luz ", 55, date(2026, 11, 13))]
        let result = RecurringDetector.suggestions(entries: entries, existingNames: [], dismissed: [], now: date(2026, 11, 21), calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 55)
        XCTAssertEqual(result.first?.name, "Luz")
        XCTAssertEqual(result.first?.dayOfMonth, 13)
        XCTAssertEqual(result.first?.monthsText, "octubre y noviembre")
        XCTAssertEqual(result.first?.datesText, "el 12 de octubre y el 13 de noviembre")
        XCTAssertEqual(result.first?.paidThisMonth, true)
        // Se pregunta el mismo dia del mes siguiente: 13 de diciembre.
        let due = result.first?.nextDueDate(calendar: calendar)
        XCTAssertEqual(due.map { calendar.component(.month, from: $0) }, 12)
        XCTAssertEqual(due.map { calendar.component(.day, from: $0) }, 13)
    }

    func testNotPaidThisMonthAsksThisMonth() {
        let entries = [entry("Internet", 35, date(2026, 9, 5)), entry("Internet", 35, date(2026, 10, 5))]
        let result = RecurringDetector.suggestions(entries: entries, existingNames: [], dismissed: [], now: date(2026, 11, 21), calendar: calendar)
        XCTAssertEqual(result.first?.paidThisMonth, false)
        let due = result.first?.nextDueDate(calendar: calendar)
        XCTAssertEqual(due.map { calendar.component(.month, from: $0) }, 11)
        XCTAssertEqual(due.map { calendar.component(.day, from: $0) }, 5)
    }

    func testDueDayClampsToShortMonths() {
        let entries = [entry("Colegio", 120, date(2026, 12, 31)), entry("Colegio", 120, date(2027, 1, 31))]
        let result = RecurringDetector.suggestions(entries: entries, existingNames: [], dismissed: [], now: date(2027, 1, 31), calendar: calendar)
        let due = result.first?.nextDueDate(calendar: calendar)
        XCTAssertEqual(due.map { calendar.component(.day, from: $0) }, 28)
    }

    func testSuggestedReminderWhenDayAlreadyPassed() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 15))!
        let past = date(2026, 11, 5)
        let reminder = NotificationManager.suggestedReminderDate(due: past, now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: reminder), 22)
        XCTAssertEqual(calendar.component(.hour, from: reminder), 9)
        let future = date(2026, 12, 13)
        XCTAssertEqual(NotificationManager.suggestedReminderDate(due: future, now: now, calendar: calendar), future)
    }

    func testIgnoresFrequentPurchasesExistingAndDismissed() {
        let now = date(2026, 11, 21)
        let groceries = [entry("Super", 40, date(2026, 10, 3)), entry("Super", 35, date(2026, 10, 20)), entry("Super", 42, date(2026, 11, 5))]
        XCTAssertTrue(RecurringDetector.suggestions(entries: groceries, existingNames: [], dismissed: [], now: now, calendar: calendar).isEmpty)

        let netflix = [entry("Netflix", 15, date(2026, 10, 8)), entry("Netflix", 15, date(2026, 11, 8))]
        XCTAssertTrue(RecurringDetector.suggestions(entries: netflix, existingNames: ["Netflix"], dismissed: [], now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(RecurringDetector.suggestions(entries: netflix, existingNames: [], dismissed: ["netflix"], now: now, calendar: calendar).isEmpty)
    }

    func testIgnoresNonConsecutiveOrVeryDifferentAmounts() {
        let now = date(2026, 11, 21)
        let gap = [entry("Gimnasio", 30, date(2026, 9, 2)), entry("Gimnasio", 30, date(2026, 11, 2))]
        XCTAssertTrue(RecurringDetector.suggestions(entries: gap, existingNames: [], dismissed: [], now: now, calendar: calendar).isEmpty)

        let different = [entry("Regalo", 20, date(2026, 10, 2)), entry("Regalo", 90, date(2026, 11, 2))]
        XCTAssertTrue(RecurringDetector.suggestions(entries: different, existingNames: [], dismissed: [], now: now, calendar: calendar).isEmpty)
    }
}
