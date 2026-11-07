import XCTest
@testable import MonAvi

/// Logica pura del catalogo de canje: cashback faltante y sus textos, orden, filtros,
/// "Como llegar", estados de un canje y el decodificado de los embeds
/// de PostgREST (`partner_merchants`, `reward_items`).
final class RewardsTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func merchant(
        name: String,
        category: String? = nil,
        address: String? = nil,
        mapsUrl: String? = nil,
        currency: RewardCurrency? = nil
    ) -> PartnerMerchant {
        PartnerMerchant(
            id: UUID(),
            name: name,
            ruc: "155-1-2024",
            status: "active",
            logoUrl: nil,
            mapsUrl: mapsUrl,
            category: category,
            address: address,
            createdAt: Date(),
            updatedAt: Date(),
            rewardCurrency: currency
        )
    }

    private func item(name: String, merchant: PartnerMerchant?, sortOrder: Int = 0, cost: Int = 100) -> RewardItem {
        RewardItem(
            id: UUID(),
            merchantId: merchant?.id ?? UUID(),
            name: name,
            itemDescription: nil,
            photoUrl: nil,
            pointsCost: cost,
            status: "active",
            sortOrder: sortOrder,
            merchant: merchant
        )
    }

    // MARK: - Donde canjear (agrupado por comercio)

    func testMerchantSummaryGroupsItemsInCatalogOrder() {
        let cafe = merchant(name: "Café Uno", currency: .puntos)
        let panaderia = merchant(name: "Panadería Dos")
        let items = [
            item(name: "Capuchino", merchant: cafe, cost: 150),
            item(name: "Pan", merchant: panaderia, cost: 300),
            item(name: "Galleta", merchant: cafe, cost: 80),
        ]

        let summaries = PartnerMerchantSummary.group(items)

        XCTAssertEqual(summaries.map(\.name), ["Café Uno", "Panadería Dos"])
        XCTAssertEqual(summaries[0].items.count, 2)
        XCTAssertEqual(summaries[0].cheapestCost, 80)
        XCTAssertEqual(summaries[0].currency, .puntos)
        XCTAssertEqual(summaries[1].currency, .cashback)
    }

    func testMerchantSummaryEmptyCatalog() {
        XCTAssertTrue(PartnerMerchantSummary.group([]).isEmpty)
    }

    // MARK: - Cashback faltante (en centavos)

    func testPointsMissing() {
        XCTAssertEqual(RewardsMath.pointsMissing(cost: 150, balance: 100), 50)
        XCTAssertEqual(RewardsMath.pointsMissing(cost: 150, balance: 150), 0)
        XCTAssertEqual(RewardsMath.pointsMissing(cost: 150, balance: 400), 0)
        XCTAssertEqual(RewardsMath.pointsMissing(cost: 150, balance: -20), 150)
    }

    func testCanAfford() {
        XCTAssertTrue(RewardsMath.canAfford(cost: 100, balance: 100))
        XCTAssertFalse(RewardsMath.canAfford(cost: 101, balance: 100))
    }

    // MARK: - Textos de cashback (centavos -> dolares)

    func testBalanceText() {
        XCTAssertEqual(RewardsMath.balanceText(cents: 650), "Tienes $6.50 de cashback")
        XCTAssertEqual(RewardsMath.balanceText(cents: 0), "Tienes $0.00 de cashback")
    }

    func testMissingText() {
        XCTAssertEqual(RewardsMath.missingText(cost: 350, balance: 230), "Te faltan $1.20")
        XCTAssertNil(RewardsMath.missingText(cost: 350, balance: 350))
        XCTAssertNil(RewardsMath.missingText(cost: 350, balance: 1000))
    }

    func testConfirmationTitle() {
        XCTAssertEqual(
            RewardsMath.confirmationTitle(itemName: "Capuchino", merchantName: "Café X", cost: 350),
            "¿Canjear Capuchino en Café X por $3.50 de cashback?"
        )
    }

    // MARK: - Dos monedas (cashback y puntos)

    func testCurrencyFormatting() {
        XCTAssertEqual(RewardCurrency.cashback.format(350), "$3.50")
        XCTAssertEqual(RewardCurrency.puntos.format(150), "150 pts")
        XCTAssertEqual(RewardCurrency.puntos.format(1500), "1,500 pts")
        XCTAssertEqual(RewardCurrency.puntos.badgeText, "Canje con puntos")
        XCTAssertEqual(RewardCurrency.cashback.badgeText, "Canje con cashback")
    }

    func testMissingTextAndConfirmationInPoints() {
        XCTAssertEqual(RewardsMath.missingText(cost: 150, balance: 120, currency: .puntos), "Te faltan 30 pts")
        XCTAssertEqual(
            RewardsMath.confirmationTitle(itemName: "Capuchino", merchantName: "Café X", cost: 150, currency: .puntos),
            "¿Canjear Capuchino en Café X por 150 pts?"
        )
    }

    func testAffordabilityUsesTheMerchantCurrency() {
        let puntosItem = item(name: "Galleta", merchant: merchant(name: "M1", currency: .puntos), cost: 200)
        let cashbackItem = item(name: "Café", merchant: merchant(name: "M2", currency: .cashback), cost: 200)
        let defaultItem = item(name: "Jugo", merchant: merchant(name: "M3"), cost: 200)

        XCTAssertEqual(puntosItem.currency, .puntos)
        XCTAssertEqual(defaultItem.currency, .cashback)
        XCTAssertEqual(puntosItem.formattedCost, "200 pts")
        XCTAssertEqual(cashbackItem.formattedCost, "$2.00")

        // 500 centavos de cashback, 50 puntos.
        XCTAssertFalse(RewardsMath.canAfford(item: puntosItem, cashbackCents: 500, habitPoints: 50))
        XCTAssertTrue(RewardsMath.canAfford(item: cashbackItem, cashbackCents: 500, habitPoints: 50))
        XCTAssertEqual(RewardsMath.pointsMissing(item: puntosItem, cashbackCents: 500, habitPoints: 50), 150)

        let balance = PointsBalance(userId: UUID(), confirmedPoints: 500, pendingPoints: 0, habitPoints: 50, habitPointsEarned: 80)
        XCTAssertEqual(balance.spendable(in: .puntos), 50)
        XCTAssertEqual(balance.spendable(in: .cashback), 500)
    }

    func testFeaturedPrefersAffordableThenNearest() {
        let cafe = merchant(name: "Café", currency: .cashback)
        let tienda = merchant(name: "Tienda", currency: .puntos)
        let items = [
            item(name: "Lejos", merchant: cafe, cost: 5_000),
            item(name: "Cerca", merchant: tienda, cost: 120),
            item(name: "Alcanza barato", merchant: cafe, cost: 100),
            item(name: "Alcanza caro", merchant: tienda, cost: 90),
        ]
        let featured = RewardsMath.featured(items, cashbackCents: 300, habitPoints: 100, limit: 3)
        XCTAssertEqual(featured.map(\.name), ["Alcanza barato", "Alcanza caro", "Cerca"])
    }

    // MARK: - QR del canje

    func testRedeemURLEncodesCode() throws {
        let url = try XCTUnwrap(RewardsMath.redeemURL(code: "AB23CD"))
        XCTAssertEqual(url.absoluteString, "https://monavi.maday.app/canjear?code=AB23CD")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "code" })?.value, "AB23CD")
    }

    // MARK: - Orden y filtros

    func testSortedByMerchantThenSortOrder() {
        let cafe = merchant(name: "Café Duran")
        let bakery = merchant(name: "Arrocha")
        let items = [
            item(name: "Latte", merchant: cafe, sortOrder: 2),
            item(name: "Espresso", merchant: cafe, sortOrder: 1),
            item(name: "Jabón", merchant: bakery, sortOrder: 5),
        ]
        let sorted = RewardsMath.sorted(items).map(\.name)
        XCTAssertEqual(sorted, ["Jabón", "Espresso", "Latte"])
    }

    func testCategoriesAreDistinctTrimmedAndSorted() {
        let items = [
            item(name: "A", merchant: merchant(name: "M1", category: "Restaurantes")),
            item(name: "B", merchant: merchant(name: "M2", category: " Cafés ")),
            item(name: "C", merchant: merchant(name: "M3", category: "Restaurantes")),
            item(name: "D", merchant: merchant(name: "M4", category: "")),
            item(name: "E", merchant: nil),
        ]
        XCTAssertEqual(RewardsMath.categories(of: items), ["Cafés", "Restaurantes"])
    }

    func testFilterByCategory() {
        let items = [
            item(name: "A", merchant: merchant(name: "M1", category: "Restaurantes")),
            item(name: "B", merchant: merchant(name: "M2", category: "Cafés")),
        ]
        XCTAssertEqual(RewardsMath.filter(items, category: nil).count, 2)
        XCTAssertEqual(RewardsMath.filter(items, category: "Cafés").map(\.name), ["B"])
    }

    // MARK: - Como llegar

    func testDirectionsPrefersMerchantMapsURL() {
        let url = RewardsMath.directionsURL(
            name: "Café Duran",
            address: "Calle 50",
            mapsUrl: "https://maps.app.goo.gl/abc123"
        )
        XCTAssertEqual(url?.absoluteString, "https://maps.app.goo.gl/abc123")
    }

    func testDirectionsFallsBackToAppleMapsSearch() throws {
        let url = try XCTUnwrap(RewardsMath.directionsURL(name: "Café Duran", address: "Calle 50", mapsUrl: "  "))
        XCTAssertEqual(url.host, "maps.apple.com")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "Café Duran, Calle 50")
    }

    func testDirectionsIgnoresNonWebMapsURL() throws {
        let url = try XCTUnwrap(RewardsMath.directionsURL(name: "Tienda", address: nil, mapsUrl: "javascript:alert(1)"))
        XCTAssertEqual(url.host, "maps.apple.com")
    }

    // MARK: - Estados de un canje

    func testRedemptionStatusDisplayNames() {
        XCTAssertEqual(RewardRedemptionStatus.emitido.displayName, "Listo para usar")
        XCTAssertEqual(RewardRedemptionStatus.entregado.displayName, "Entregado")
        XCTAssertEqual(RewardRedemptionStatus.cancelado.displayName, "Cancelado")
        XCTAssertEqual(RewardRedemptionStatus.vencido.displayName, "Vencido")
    }

    // MARK: - Decodificado (claves de PostgREST)

    func testDecodesRewardItemWithEmbeddedMerchant() throws {
        let json = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "merchant_id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
          "name": "Café latte",
          "description": "Grande, con leche de almendras",
          "photo_url": "https://example.com/latte.jpg",
          "points_cost": 150,
          "status": "active",
          "sort_order": 1,
          "created_at": "2026-11-01T10:00:00Z",
          "updated_at": "2026-11-01T10:00:00Z",
          "partner_merchants": {
            "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
            "name": "Café Duran",
            "ruc": "155-1-2024",
            "status": "active",
            "logo_url": null,
            "maps_url": "https://maps.app.goo.gl/abc",
            "category": "Cafés",
            "address": "Calle 50",
            "created_at": "2026-11-01T10:00:00Z",
            "updated_at": "2026-11-01T10:00:00Z"
          }
        }
        """
        let decoded = try decoder.decode(RewardItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pointsCost, 150)
        XCTAssertEqual(decoded.itemDescription, "Grande, con leche de almendras")
        XCTAssertEqual(decoded.merchantName, "Café Duran")
        XCTAssertEqual(decoded.merchant?.category, "Cafés")
    }

    func testDecodesMerchantRewardCurrency() throws {
        func merchantJSON(_ currency: String?) -> String {
            let field = currency.map { ", \"reward_currency\": \($0)" } ?? ""
            return """
            {
              "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
              "name": "Café Duran",
              "ruc": "155-1-2024",
              "status": "active",
              "created_at": "2026-11-01T10:00:00Z",
              "updated_at": "2026-11-01T10:00:00Z"\(field)
            }
            """
        }
        let puntos = try decoder.decode(PartnerMerchant.self, from: Data(merchantJSON("\"puntos\"").utf8))
        XCTAssertEqual(puntos.currency, .puntos)
        let cashback = try decoder.decode(PartnerMerchant.self, from: Data(merchantJSON("\"cashback\"").utf8))
        XCTAssertEqual(cashback.currency, .cashback)
        let null = try decoder.decode(PartnerMerchant.self, from: Data(merchantJSON("null").utf8))
        XCTAssertEqual(null.currency, .cashback)
        let missing = try decoder.decode(PartnerMerchant.self, from: Data(merchantJSON(nil).utf8))
        XCTAssertEqual(missing.currency, .cashback)
        let unknown = try decoder.decode(PartnerMerchant.self, from: Data(merchantJSON("\"millas\"").utf8))
        XCTAssertEqual(unknown.currency, .cashback)
    }

    func testDecodesPointsBalanceWithAndWithoutHabitColumns() throws {
        let full = """
        {"user_id": "2F9619FF-8B86-D011-B42D-00C04FC964FF", "confirmed_points": 650, "pending_points": 120,
         "habit_points": 340, "habit_points_earned": 900}
        """
        let balance = try decoder.decode(PointsBalance.self, from: Data(full.utf8))
        XCTAssertEqual(balance.confirmedPoints, 650)
        XCTAssertEqual(balance.pendingPoints, 120)
        XCTAssertEqual(balance.habitPoints, 340)
        XCTAssertEqual(balance.habitPointsEarned, 900)

        let old = """
        {"user_id": "2F9619FF-8B86-D011-B42D-00C04FC964FF", "confirmed_points": 650, "pending_points": 0}
        """
        let legacy = try decoder.decode(PointsBalance.self, from: Data(old.utf8))
        XCTAssertEqual(legacy.habitPoints, 0)
        XCTAssertEqual(legacy.habitPointsEarned, 0)
    }

    private func redemptionJSON(status: String, expiresAt: String, withItem: Bool, currency: String? = nil) -> String {
        let currencyField = currency.map { ",\n  \"currency\": \"\($0)\"" } ?? ""
        let itemJSON = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "merchant_id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
          "name": "Café latte",
          "description": null,
          "photo_url": null,
          "points_cost": 150,
          "status": "active",
          "sort_order": 0,
          "partner_merchants": null
        }
        """
        let itemValue = withItem ? itemJSON : "null"
        return """
        {
          "id": "1F9619FF-8B86-D011-B42D-00C04FC964FF",
          "user_id": "2F9619FF-8B86-D011-B42D-00C04FC964FF",
          "reward_item_id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "merchant_id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
          "points_cost": 150,
          "code": "AB23CD",
          "status": "\(status)",
          "expires_at": "\(expiresAt)",
          "delivered_at": null,
          "created_at": "2026-11-01T10:00:00Z",
          "reward_items": \(itemValue)\(currencyField)
        }
        """
    }

    func testDecodesRedemptionAndFallsBackWhenItemIsHidden() throws {
        let withItem = try decoder.decode(
            RewardRedemption.self,
            from: Data(redemptionJSON(status: "emitido", expiresAt: "2099-01-01T00:00:00Z", withItem: true).utf8)
        )
        XCTAssertEqual(withItem.code, "AB23CD")
        XCTAssertEqual(withItem.itemName, "Café latte")
        XCTAssertTrue(withItem.isUsable())

        let withoutItem = try decoder.decode(
            RewardRedemption.self,
            from: Data(redemptionJSON(status: "entregado", expiresAt: "2099-01-01T00:00:00Z", withItem: false).utf8)
        )
        XCTAssertNil(withoutItem.item)
        XCTAssertEqual(withoutItem.merchantName, "Comercio aliado")
        XCTAssertFalse(withoutItem.isUsable())
    }

    func testDecodesRedemptionCurrency() throws {
        let puntos = try decoder.decode(
            RewardRedemption.self,
            from: Data(redemptionJSON(status: "emitido", expiresAt: "2099-01-01T00:00:00Z", withItem: true, currency: "puntos").utf8)
        )
        XCTAssertEqual(puntos.displayCurrency, .puntos)
        XCTAssertEqual(puntos.formattedCost, "150 pts")

        let legacy = try decoder.decode(
            RewardRedemption.self,
            from: Data(redemptionJSON(status: "emitido", expiresAt: "2099-01-01T00:00:00Z", withItem: false).utf8)
        )
        XCTAssertEqual(legacy.displayCurrency, .cashback)
        XCTAssertEqual(legacy.formattedCost, "$1.50")
    }

    func testIssuedButExpiredRedemptionShowsAsExpired() throws {
        let redemption = try decoder.decode(
            RewardRedemption.self,
            from: Data(redemptionJSON(status: "emitido", expiresAt: "2026-01-01T00:00:00Z", withItem: false).utf8)
        )
        let now = ISO8601DateFormatter().date(from: "2026-02-01T00:00:00Z")!
        XCTAssertEqual(redemption.effectiveStatus(now: now), .vencido)
        XCTAssertFalse(redemption.isUsable(now: now))

        let before = ISO8601DateFormatter().date(from: "2025-12-01T00:00:00Z")!
        XCTAssertEqual(redemption.effectiveStatus(now: before), .emitido)
    }
}
