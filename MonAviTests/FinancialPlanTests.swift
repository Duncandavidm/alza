import XCTest
@testable import MonAvi

final class FinancialPlanTests: XCTestCase {
    private func plan(
        income: Decimal = 1500, fixed: Decimal = 600, debts: [FinancialSnapshot.DebtInput] = [],
        cash: Decimal = 0, savings: Decimal = 0, realSpending: Decimal? = 1000, realIncome: Decimal? = 1500,
        accounts: Int = 1, transactions: Int = 40, days: Int = 22, budgets: Int = 3, variable: Bool = false
    ) -> FinancialPlan {
        var snapshot = FinancialSnapshot(monthlyIncome: income, fixedExpenses: fixed, debts: debts, cash: cash, savings: savings)
        snapshot.hasVariableIncome = variable
        snapshot.realIncome = realIncome
        snapshot.realSpending = realSpending
        snapshot.realMonths = realSpending == nil ? 0 : 3
        return FinancialPlan(.init(snapshot: snapshot, accountsCount: accounts, recentTransactions: transactions,
                                   trackedDays30: days, budgetsCount: budgets))
    }

    func testNewUserStartsAtStepOne() {
        let p = plan(realSpending: nil, realIncome: nil, transactions: 5, days: 3, budgets: 0)
        XCTAssertEqual(p.currentStep?.number, 1)
        XCTAssertFalse(p.readiness.isReady)
    }

    func testExpensiveCardBlocksInvestingWithAnnualRate() {
        let card = FinancialSnapshot.DebtInput(name: "Visa", balance: 900, monthlyRate: 2)
        let p = plan(debts: [card], cash: 5000)
        XCTAssertFalse(p.readiness.isReady)
        XCTAssertTrue(p.readiness.blockers.contains { $0.contains("Visa") && $0.contains("24%") })
        XCTAssertEqual(p.currentStep?.number, 5)
    }

    func testCheapDebtDoesNotBlock() {
        let loan = FinancialSnapshot.DebtInput(name: "Auto", balance: 8000, monthlyRate: Decimal(string: "0.7"))
        let p = plan(debts: [loan], cash: 4000)
        XCTAssertTrue(p.expensiveDebts.isEmpty)
    }

    func testEmergencyFundSteps() {
        // Gasta 1000 al mes: con 1500 tiene el colchón inicial pero no el completo (3000).
        let p = plan(cash: 1500)
        XCTAssertEqual(p.steps[3].status, .done)
        XCTAssertEqual(p.currentStep?.number, 6)
        XCTAssertTrue(p.readiness.blockers.contains { $0.contains("fondo de emergencia") })
    }

    func testReadyToInvest() {
        let p = plan(cash: 3500)
        XCTAssertTrue(p.readiness.isReady)
        XCTAssertEqual(p.completedCount, 7)
        XCTAssertNil(p.currentStep)
    }

    func testVariableIncomeNeedsSixMonths() {
        let p = plan(cash: 3500, variable: true)
        XCTAssertNotEqual(p.steps[5].status, .done)
    }

    func testOverspendingBlocks() {
        let p = plan(cash: 9000, realSpending: 1800, realIncome: 1500)
        XCTAssertTrue(p.readiness.blockers.contains { $0.contains("gastas") })
    }

    func testTrackedDaysCountsDistinctDays() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let dates = [now, now.addingTimeInterval(-3600), now.addingTimeInterval(-86400 * 2), now.addingTimeInterval(-86400 * 40)]
        XCTAssertEqual(FinancialPlanLoader.trackedDays(dates, now: now), 2)
    }
}
