import XCTest
@testable import MonAvi

final class HabitEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let userId = UUID()
    private let accountId = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var engine: HabitEngine {
        HabitEngine(calendar: calendar, now: date(2026, 11, 15))
    }

    private func transaction(
        _ amount: Decimal,
        _ type: MovementType,
        category: String? = nil,
        occurred: Date,
        created: Date? = nil
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            userId: userId,
            accountId: accountId,
            amount: type.signedAmount(from: amount),
            movementType: type,
            category: category,
            description: nil,
            tags: [],
            originalCurrency: nil,
            originalAmount: nil,
            occurredAt: occurred,
            createdAt: created ?? occurred
        )
    }

    private func goal(target: Decimal = 100) -> SavingsGoal {
        SavingsGoal(
            id: UUID(),
            userId: userId,
            name: "Viaje",
            emoji: "✈️",
            targetAmount: target,
            targetDate: "2027-06-01",
            currentAmount: 0,
            accountId: nil,
            createdAt: date(2026, 9, 1),
            updatedAt: date(2026, 9, 1)
        )
    }

    private func contribution(_ amount: Decimal, goal: SavingsGoal, on date: Date) -> SavingsContribution {
        SavingsContribution(id: UUID(), userId: userId, goalId: goal.id, amount: amount, createdAt: date)
    }

    private func input(
        transactions: [FinanceTransaction] = [],
        budgets: [Budget] = [],
        goals: [SavingsGoal] = [],
        contributions: [SavingsContribution] = [],
        receipts: [Date] = []
    ) -> HabitEngine.Input {
        HabitEngine.Input(
            transactions: transactions,
            budgets: budgets,
            goals: goals,
            contributions: contributions,
            verifiedReceiptDates: receipts
        )
    }

    // MARK: - Racha

    func testStreakUsesCreatedAtNotOccurredAt() {
        let transactions = [
            transaction(5, .gasto, occurred: date(2026, 11, 15)),
            transaction(5, .gasto, occurred: date(2026, 11, 14)),
            transaction(5, .gasto, occurred: date(2026, 11, 13)),
            // Fechado hacia atras, pero anotado hoy: no alarga la racha.
            transaction(5, .gasto, occurred: date(2026, 11, 12), created: date(2026, 11, 15)),
        ]
        let progress = engine.progress(for: input(transactions: transactions))
        XCTAssertEqual(progress.currentStreak, 3)
        XCTAssertEqual(progress.xpBySource[.logging], 3 * HabitEngine.Rules.xpPerLoggedDay)
    }

    func testStreakStillCountsIfTodayNotLoggedYet() {
        let transactions = [
            transaction(5, .gasto, occurred: date(2026, 11, 14)),
            transaction(5, .gasto, occurred: date(2026, 11, 13)),
        ]
        XCTAssertEqual(engine.progress(for: input(transactions: transactions)).currentStreak, 2)
    }

    // MARK: - Ahorro

    func testBackedContributionMaturesAfter30Days() {
        let viaje = goal()
        let progress = engine.progress(for: input(
            transactions: [
                transaction(1000, .ingreso, occurred: date(2026, 10, 1)),
                transaction(200, .gasto, occurred: date(2026, 10, 2)),
            ],
            goals: [viaje],
            contributions: [contribution(100, goal: viaje, on: date(2026, 10, 5))]
        ))
        XCTAssertEqual(progress.contributionReviews.first?.status, .matured)
        XCTAssertEqual(progress.xpBySource[.savings], HabitEngine.Rules.xpPerSavingsWeek)
        XCTAssertTrue(progress.badges.first { $0.id == "goal_done" }!.isEarned)
    }

    func testContributionWithoutRecordedIncomeDoesNotCount() {
        let viaje = goal()
        let progress = engine.progress(for: input(
            goals: [viaje],
            contributions: [contribution(100, goal: viaje, on: date(2026, 10, 5))]
        ))
        XCTAssertEqual(progress.contributionReviews.first?.status, .unbacked)
        XCTAssertNil(progress.xpBySource[.savings])
    }

    func testContributionsAboveMonthlySurplusDoNotCount() {
        let viaje = goal()
        let progress = engine.progress(for: input(
            transactions: [transaction(150, .ingreso, occurred: date(2026, 10, 1))],
            goals: [viaje],
            contributions: [
                contribution(100, goal: viaje, on: date(2026, 10, 5)),
                contribution(100, goal: viaje, on: date(2026, 10, 6)),
            ]
        ))
        let statuses = progress.contributionReviews.map(\.status)
        XCTAssertEqual(statuses.filter { $0 == .matured }.count, 1)
        XCTAssertEqual(statuses.filter { $0 == .unbacked }.count, 1)
    }

    func testWithdrawalBeforeMaturingBreaksContribution() {
        let viaje = goal()
        let progress = engine.progress(for: input(
            transactions: [transaction(1000, .ingreso, occurred: date(2026, 10, 1))],
            goals: [viaje],
            contributions: [
                contribution(100, goal: viaje, on: date(2026, 10, 5)),
                contribution(-50, goal: viaje, on: date(2026, 10, 15)),
            ]
        ))
        XCTAssertEqual(progress.contributionReviews.first?.status, .broken)
        XCTAssertNil(progress.xpBySource[.savings])
    }

    func testRecentContributionIsMaturing() {
        let viaje = goal()
        let progress = engine.progress(for: input(
            transactions: [transaction(1000, .ingreso, occurred: date(2026, 11, 1))],
            goals: [viaje],
            contributions: [contribution(100, goal: viaje, on: date(2026, 11, 10))]
        ))
        XCTAssertEqual(progress.contributionReviews.first?.status, .maturing(on: date(2026, 12, 10)))
    }

    // MARK: - Presupuestos

    func testMonthlyBudgetNeedsLoggingToCount() {
        let budget = Budget(
            id: UUID(),
            userId: userId,
            category: "Comida",
            period: .monthly,
            limitAmount: 300,
            color: nil,
            createdAt: date(2026, 9, 20),
            updatedAt: date(2026, 9, 20)
        )

        // Octubre: 12 dias anotados, 250 en comida -> cumplido.
        var transactions = (1...12).map { day in
            transaction(10, .gasto, category: "Otro", occurred: date(2026, 10, day))
        }
        transactions.append(transaction(250, .gasto, category: "Comida", occurred: date(2026, 10, 20)))

        let met = engine.progress(for: input(transactions: transactions, budgets: [budget]))
        XCTAssertEqual(met.xpBySource[.budgets], HabitEngine.Rules.xpPerMonthlyBudgetMet)

        // Un mes sin anotar casi nada no cuenta como "cumplido".
        let empty = engine.progress(for: input(
            transactions: [transaction(10, .gasto, category: "Comida", occurred: date(2026, 10, 3))],
            budgets: [budget]
        ))
        XCTAssertNil(empty.xpBySource[.budgets])
    }

    // MARK: - Tope y niveles

    func testMonthlyCap() {
        let receipts = (0..<60).map { _ in date(2026, 10, 10) }
        let progress = engine.progress(for: input(receipts: receipts))
        XCTAssertEqual(progress.totalXP, HabitEngine.Rules.monthlyXPCap)
    }

    func testLevels() {
        XCTAssertEqual(HabitLevel.level(forXP: 0).number, 1)
        XCTAssertEqual(HabitLevel.level(forXP: 99).number, 1)
        XCTAssertEqual(HabitLevel.level(forXP: 100).number, 2)
        XCTAssertEqual(HabitLevel.level(forXP: 100_000).number, 10)
        XCTAssertNil(HabitLevel.level(forXP: 100_000).nextLevelXP)
        XCTAssertEqual(HabitLevel.level(forXP: 175).progress(xp: 175), 0.5, accuracy: 0.001)
    }
}
