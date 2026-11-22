import XCTest
@testable import MonAvi

final class InvoiceMonthSummaryTests: XCTestCase {
    func testHeadlineWithCashback() {
        let summary = InvoiceMonthSummary(month: "2026-11", receipts: 12, spent: 420.5, cashbackCents: 840, merchantCount: 5)
        XCTAssertEqual(InvoiceMonthSummaryText.headline(summary, isCurrent: true), "Este mes gané $8.40 de cashback con mis facturas")
        XCTAssertEqual(InvoiceMonthSummaryText.headline(summary, isCurrent: false), "En noviembre gané $8.40 de cashback con mis facturas")
    }

    func testHeadlineWithoutCashback() {
        let summary = InvoiceMonthSummary(month: "2026-10", receipts: 1, spent: 10, cashbackCents: 0, merchantCount: 1)
        XCTAssertEqual(InvoiceMonthSummaryText.headline(summary, isCurrent: false), "En octubre escaneé 1 factura con MonAvi")
    }

    func testShareTextIncludesCodeAndLink() {
        let summary = InvoiceMonthSummary(month: "2026-11", receipts: 3, spent: 30, cashbackCents: 120, merchantCount: 2)
        let text = InvoiceMonthSummaryText.shareText(summary, isCurrent: true, code: "ABC123")
        XCTAssertTrue(text.contains("ABC123"))
        XCTAssertTrue(text.contains(Config.appStoreURL.absoluteString))
        XCTAssertFalse(text.contains("DGI"))
        XCTAssertFalse(text.contains("1%"))
    }

    func testRecentMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        XCTAssertEqual(InvoiceMonthSummaryText.recentMonths(from: date, count: 3, calendar: calendar), ["2026-02", "2026-01", "2025-12"])
        XCTAssertEqual(InvoiceMonthSummaryText.monthName("2026-12"), "diciembre")
        XCTAssertEqual(InvoiceMonthSummaryText.money(1234.5), "$1,234.50")
    }
}

final class PurchaseComparisonTests: XCTestCase {
    func testNormalizesNames() {
        XCTAssertEqual(PurchaseComparison.normalized("LECHE  Entera 1L*"), "leche entera 1l")
        XCTAssertEqual(PurchaseComparison.normalized("Café Molido"), "cafe molido")
    }

    func testGroupsAndFindsCheapest() {
        let now = Date()
        let purchases = [
            Purchase(description: "Leche Entera 1L", merchant: "Super A", unitPrice: 1.45, boughtAt: now),
            Purchase(description: "LECHE ENTERA 1L", merchant: "Super B", unitPrice: 1.25, boughtAt: now.addingTimeInterval(-86_400)),
            Purchase(description: "Leche entera 1l", merchant: "Super A", unitPrice: 1.35, boughtAt: now.addingTimeInterval(-10 * 86_400)),
            Purchase(description: "Pan", merchant: "Panadería", unitPrice: 0.5, boughtAt: now),
            Purchase(description: "Bolsa", merchant: "Super A", unitPrice: 0, boughtAt: now),
        ]
        let groups = PurchaseComparison.group(purchases)
        XCTAssertEqual(groups.count, 2)
        let milk = groups[0]
        XCTAssertEqual(milk.key, "leche entera 1l")
        XCTAssertEqual(milk.purchases, 3)
        XCTAssertEqual(milk.cheapest?.merchant, "Super B")
        XCTAssertEqual(milk.offers.last?.merchant, "Super A")
        XCTAssertEqual(milk.offers.last?.lastPrice, 1.45)
        XCTAssertEqual(milk.offers.last?.lowestPrice, 1.35)
        XCTAssertEqual(milk.savingsPerUnit, 0.20, accuracy: 0.0001)
        XCTAssertEqual(PurchaseComparison.summary(milk), "Más barato en Super B: $1.25")
        XCTAssertEqual(PurchaseComparison.summary(groups[1]), "$0.50 en Panadería")
    }
}
