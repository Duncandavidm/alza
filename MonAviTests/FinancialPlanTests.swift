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
                                   trackedDays30: days, budgetsCount: budgets), country: .panama)
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

    func testColombiaUsesHigherExpensiveThreshold() {
        var snapshot = FinancialSnapshot(monthlyIncome: 3_000_000, fixedExpenses: 1_200_000,
                                         debts: [.init(name: "Crédito", balance: 2_000_000, monthlyRate: Decimal(string: "1.7"))],
                                         cash: 0, savings: 0)
        snapshot.realSpending = 2_000_000
        snapshot.realIncome = 3_000_000
        snapshot.realMonths = 3
        let inputs = FinancialPlan.Inputs(snapshot: snapshot, accountsCount: 1, recentTransactions: 40, trackedDays30: 22, budgetsCount: 3)
        XCTAssertTrue(FinancialPlan(inputs, country: .colombia).expensiveDebts.isEmpty)
        XCTAssertEqual(FinancialPlan(inputs, country: .panama).expensiveDebts.count, 1)
        // Colombia redondea lo que hay que apartar a montos en pesos.
        XCTAssertTrue(FinancialPlan(inputs, country: .colombia).steps[3].mission.contains("000"))
    }

    func testTrackedDaysCountsDistinctDays() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let dates = [now, now.addingTimeInterval(-3600), now.addingTimeInterval(-86400 * 2), now.addingTimeInterval(-86400 * 40)]
        XCTAssertEqual(FinancialPlanLoader.trackedDays(dates, now: now), 2)
    }
}
