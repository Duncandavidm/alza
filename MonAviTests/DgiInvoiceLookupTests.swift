import XCTest
@testable import MonAvi

/// Logica pura de "leer tu factura" (lookup-dgi-receipt): mapeo de
/// categorias, interpretacion de la respuesta y reparto exacto en
/// centavos al separar por categoria.
final class DgiInvoiceLookupTests: XCTestCase {

    // MARK: - Categoria

    func testCategoryMapsKnownRawValues() {
        XCTAssertEqual(DgiInvoiceLookupLogic.category(from: "Supermercado"), .groceries)
        XCTAssertEqual(DgiInvoiceLookupLogic.category(from: "Salud"), .health)
        XCTAssertEqual(DgiInvoiceLookupLogic.category(from: " Comida "), .food)
    }

    func testCategoryUnknownEmptyOrIncomeIsNil() {
        XCTAssertNil(DgiInvoiceLookupLogic.category(from: nil))
        XCTAssertNil(DgiInvoiceLookupLogic.category(from: ""))
        XCTAssertNil(DgiInvoiceLookupLogic.category(from: "Ferretería"))
        XCTAssertNil(DgiInvoiceLookupLogic.category(from: "supermercado"))
        XCTAssertNil(DgiInvoiceLookupLogic.category(from: "Ingreso"))
    }

    // MARK: - Montos

    func testDecimalFromDollarsRoundsToCents() {
        XCTAssertEqual(DgiInvoiceLookupLogic.decimal(fromDollars: 12.34), Decimal(string: "12.34"))
        XCTAssertEqual(DgiInvoiceLookupLogic.decimal(fromDollars: 0.1 + 0.2), Decimal(string: "0.3"))
        XCTAssertEqual(DgiInvoiceLookupLogic.decimal(fromDollars: 7), Decimal(7))
    }

    func testAmountText() {
        XCTAssertEqual(DgiInvoiceLookupLogic.amountText(for: Decimal(string: "12.5")!), "12.50")
        XCTAssertEqual(DgiInvoiceLookupLogic.amountText(for: Decimal(string: "0.07")!), "0.07")
        XCTAssertEqual(DgiInvoiceLookupLogic.amountText(for: Decimal(1234)), "1234.00")
    }

    // MARK: - Reparto en centavos

    func testAllocateKeepsExactTotal() {
        let shares = DgiInvoiceLookupLogic.allocate(totalCents: 1000, weights: [1, 1, 1])
        XCTAssertEqual(shares.reduce(0, +), 1000)
        XCTAssertEqual(shares, [334, 333, 333])
    }

    func testAllocateIsProportional() {
        let shares = DgiInvoiceLookupLogic.allocate(totalCents: 2000, weights: [1500, 500])
        XCTAssertEqual(shares, [1500, 500])
    }

    func testAllocateScalesToEditedTotal() {
        // Desglose de $15.00 + $5.00 pero el usuario dejo $21.01.
        let shares = DgiInvoiceLookupLogic.allocate(totalCents: 2101, weights: [1500, 500])
        XCTAssertEqual(shares.reduce(0, +), 2101)
        XCTAssertEqual(shares, [1576, 525])
    }

    func testAllocateWithZeroWeightsSplitsEvenly() {
        XCTAssertEqual(DgiInvoiceLookupLogic.allocate(totalCents: 5, weights: [0, 0]), [3, 2])
        XCTAssertEqual(DgiInvoiceLookupLogic.allocate(totalCents: 100, weights: []), [])
    }

    func testSplitLinesSumExactlyToTotalAndMergeDuplicates() {
        let breakdown = [
            DgiCategorySplitLine(categoryName: "Supermercado", category: .groceries, amount: Decimal(string: "10.00")!),
            DgiCategorySplitLine(categoryName: "Salud", category: .health, amount: Decimal(string: "3.33")!),
            DgiCategorySplitLine(categoryName: "Supermercado", category: .groceries, amount: Decimal(string: "1.00")!),
            DgiCategorySplitLine(categoryName: "Mascotas", category: .pets, amount: 0),
        ]
        let total = Decimal(string: "14.34")!
        let lines = DgiInvoiceLookupLogic.splitLines(breakdown: breakdown, total: total)

        XCTAssertEqual(lines.map(\.categoryName), ["Supermercado", "Salud"])
        // 1434 centavos repartidos 1100:333 -> 1100 + 333, y el centavo que
        // sobra va al residuo mayor (Supermercado).
        XCTAssertEqual(lines.map(\.amount), [Decimal(string: "11.01")!, Decimal(string: "3.33")!])
        XCTAssertEqual(lines.reduce(Decimal(0)) { $0 + $1.amount }, total)
    }

    func testSplitLinesOddTotal() {
        let breakdown = [
            DgiCategorySplitLine(categoryName: "A", category: nil, amount: 1),
            DgiCategorySplitLine(categoryName: "B", category: nil, amount: 1),
            DgiCategorySplitLine(categoryName: "C", category: nil, amount: 1),
        ]
        let total = Decimal(string: "0.10")!
        let lines = DgiInvoiceLookupLogic.splitLines(breakdown: breakdown, total: total)
        XCTAssertEqual(lines.reduce(Decimal(0)) { $0 + $1.amount }, total)
        XCTAssertEqual(lines.map(\.amount), [Decimal(string: "0.04")!, Decimal(string: "0.03")!, Decimal(string: "0.03")!])
    }

    func testIndexOfLargestPrefersFirstOnTie() {
        XCTAssertEqual(DgiInvoiceLookupLogic.indexOfLargest([1, 5, 5, 2]), 1)
        XCTAssertNil(DgiInvoiceLookupLogic.indexOfLargest([]))
    }

    func testSplitDescription() {
        XCTAssertEqual(
            DgiInvoiceLookupLogic.splitDescription(merchant: "Super 99", categoryName: "Supermercado"),
            "Super 99 · Supermercado"
        )
    }

    // MARK: - Respuesta de la Edge Function

    private func decode(_ json: String) throws -> DgiLookupResponse {
        try JSONDecoder().decode(DgiLookupResponse.self, from: Data(json.utf8))
    }

    func testConfirmedResponse() throws {
        let response = try decode("""
        {"status":"confirmada","merchant_name":"Super 99","amount":20.5,
         "authorized_at":"2026-11-05T14:32:00-05:00","payment_methods":["Tarjeta Crédito"],
         "items":[{"description":"Leche","quantity":2,"total":3.5,"category":"Supermercado"},
                  {"description":"Ibuprofeno","quantity":null,"total":null,"category":"Salud"}],
         "suggested_category":"Supermercado",
         "breakdown":[{"category":"Supermercado","amount":15.5},{"category":"Salud","amount":5}],
         "income_total":0,"backed_total":0,"income_backs_purchase":false}
        """)

        guard case .confirmed(let details) = DgiInvoiceLookupLogic.outcome(from: response) else {
            return XCTFail("Se esperaba confirmada")
        }
        XCTAssertEqual(details.merchantName, "Super 99")
        XCTAssertEqual(details.amount, Decimal(string: "20.5"))
        XCTAssertEqual(details.suggestedCategory, .groceries)
        XCTAssertEqual(details.paymentMethods, ["Tarjeta Crédito"])
        XCTAssertEqual(details.items.count, 2)
        XCTAssertNil(details.items[1].quantity)
        XCTAssertEqual(details.breakdown.map(\.category), [.groceries, .health])
        XCTAssertFalse(details.incomeBacksPurchase)
        XCTAssertEqual(details.authorizedAt, Date(timeIntervalSince1970: 1_793_907_120))
        XCTAssertTrue(DgiLookupOutcome.confirmed(details).showsIncomeNotice)
    }

    func testConfirmedWithUnknownCategoryAndBackedIncome() throws {
        let response = try decode("""
        {"status":"confirmada","merchant_name":null,"amount":null,"authorized_at":null,
         "payment_methods":[],"items":[],"suggested_category":"Ferretería","breakdown":[],
         "income_total":500,"backed_total":10,"income_backs_purchase":true}
        """)
        guard case .confirmed(let details) = DgiInvoiceLookupLogic.outcome(from: response) else {
            return XCTFail("Se esperaba confirmada")
        }
        XCTAssertNil(details.suggestedCategory)
        XCTAssertNil(details.merchantName)
        XCTAssertNil(details.amount)
        XCTAssertNil(details.authorizedAt)
        XCTAssertFalse(DgiLookupOutcome.confirmed(details).showsIncomeNotice)
    }

    func testPendingAndUnavailableAreManual() throws {
        let pending = DgiInvoiceLookupLogic.outcome(from: try decode(#"{"status":"pendiente","income_total":0,"backed_total":0}"#))
        XCTAssertEqual(pending, .manual(incomeTotal: 0))
        XCTAssertTrue(pending.showsIncomeNotice)

        let unavailable = DgiInvoiceLookupLogic.outcome(from: try decode(#"{"status":"no_disponible","income_total":120.25,"backed_total":0}"#))
        XCTAssertEqual(unavailable, .manual(incomeTotal: Decimal(string: "120.25")))
        XCTAssertFalse(unavailable.showsIncomeNotice)
    }

    func testDuplicate() throws {
        let outcome = DgiInvoiceLookupLogic.outcome(from: try decode(
            #"{"status":"duplicada","mine":false,"message":"Esta factura ya fue registrada por otra cuenta."}"#
        ))
        XCTAssertEqual(outcome, .duplicate(message: "Esta factura ya fue registrada por otra cuenta.", mine: false))
        XCTAssertFalse(outcome.showsIncomeNotice)
    }

    func testUnknownStatusFails() throws {
        XCTAssertEqual(DgiInvoiceLookupLogic.outcome(from: try decode(#"{"status":"otro"}"#)), .failed)
        XCTAssertFalse(DgiLookupOutcome.failed.showsIncomeNotice)
        XCTAssertFalse(DgiLookupOutcome.rateLimited.showsIncomeNotice)
    }

    // MARK: - Estado del cashback en la lista

    func testCashbackStatusDecodingAndTexts() throws {
        let decoded = try JSONDecoder().decode([DgiCashbackStatus].self, from: Data(#"["acreditado","sin_ingreso","vencido"]"#.utf8))
        XCTAssertEqual(decoded, [.acreditado, .sinIngreso, .vencido])
        XCTAssertEqual(DgiCashbackStatus.acreditado.explanation, "Cashback acreditado")
        XCTAssertEqual(DgiCashbackStatus.sinIngreso.explanation, "Cashback pendiente: registra tus ingresos para recibirlo")
        XCTAssertEqual(DgiCashbackStatus.vencido.explanation, "Cashback vencido (sin ingresos registrados)")
    }
}
