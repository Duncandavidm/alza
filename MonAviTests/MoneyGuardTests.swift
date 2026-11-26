import XCTest
@testable import MonAvi

final class MoneyGuardTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        return calendar
    }()
    private let userId = UUID()
    private let bankId = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func account(_ name: String = "Banco", type: AccountType = .checking, balance: Decimal, id: UUID? = nil) -> Account {
        Account(
            id: id ?? UUID(), userId: userId, name: name, type: type, balance: balance, currency: "USD",
            createdAt: Date(), updatedAt: Date(), debtId: nil, availableOn: nil
        )
    }

    private func tx(_ type: MovementType, _ amount: Decimal, _ category: String?, on day: Date) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(), userId: userId, accountId: bankId,
            amount: type.isInflow ? amount : -amount,
            movementType: type, category: category, description: nil, tags: [],
            originalCurrency: nil, originalAmount: nil, occurredAt: day, createdAt: day
        )
    }

    private func guardFor(accounts: [Account], transactions: [FinanceTransaction] = [], now: Date) -> MoneyGuard {
        MoneyGuard(accounts: accounts, transactions: transactions, now: now, calendar: calendar, country: .panama)
    }

    func testNegativeBankAccountIsTheFirstDanger() {
        let card = account("Visa", type: .creditCard, balance: -500)
        let bank = account(balance: -40)
        let result = guardFor(accounts: [card, bank], now: date(2026, 11, 20))
        XCTAssertEqual(result.negativeAccounts.map(\.name), ["Banco"], "La tarjeta en negativo es deuda, no alerta")
        XCTAssertEqual(result.warnings.first?.severity, .danger)
        XCTAssertEqual(result.warnings.first?.id, "negative-\(bank.id)")
    }

    func testSpendingMoreThanIncomeThisMonth() {
        let now = date(2026, 11, 20)
        let items = [
            tx(.ingreso, 800, nil, on: date(2026, 11, 1)),
            tx(.gasto, 900, "Comida", on: date(2026, 11, 10)),
        ]
        let result = guardFor(accounts: [account(balance: 100)], transactions: items, now: now)
        XCTAssertTrue(result.warnings.contains { $0.id == "overspending-month" })
    }

    func testSpendingWithoutAnyIncomeAsksWhereTheMoneyComesFrom() {
        let items = [tx(.gasto, 120, "Comida", on: date(2026, 11, 5))]
        let result = guardFor(accounts: [account(balance: 300)], transactions: items, now: date(2026, 11, 20))
        XCTAssertTrue(result.warnings.contains { $0.id == "no-income" })
    }

    func testLastMonthSalaryCountsBeforeThisMonthsArrives() {
        let items = [
            tx(.ingreso, 1000, nil, on: date(2026, 10, 30)),
            tx(.gasto, 200, "Comida", on: date(2026, 11, 3)),
        ]
        let result = guardFor(accounts: [account(balance: 800)], transactions: items, now: date(2026, 11, 4))
        XCTAssertFalse(result.warnings.contains { $0.id == "no-income" || $0.id == "overspending-month" })
    }

    func testCategorySpikeAgainstAverage() {
        var items: [FinanceTransaction] = []
        for month in 8...10 {
            items.append(tx(.ingreso, 2000, nil, on: date(2026, month, 1)))
            items.append(tx(.gasto, 100, "Restaurantes", on: date(2026, month, 12)))
        }
        items.append(tx(.ingreso, 2000, nil, on: date(2026, 11, 1)))
        items.append(tx(.gasto, 190, "Restaurantes", on: date(2026, 11, 15)))
        let result = guardFor(accounts: [account(balance: 1500)], transactions: items, now: date(2026, 11, 20))
        XCTAssertEqual(result.categorySpikes.first?.category, "Restaurantes")
        XCTAssertEqual(result.categorySpikes.first?.percentAbove, 90)
    }

    func testNormalMonthHasNoWarnings() {
        var items: [FinanceTransaction] = []
        for month in 8...11 {
            items.append(tx(.ingreso, 2000, nil, on: date(2026, month, 1)))
            items.append(tx(.gasto, 300, "Supermercado", on: date(2026, month, 5)))
        }
        let result = guardFor(accounts: [account(balance: 1500)], transactions: items, now: date(2026, 11, 20))
        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings.map(\.id))")
    }
}
