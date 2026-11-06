import XCTest
@testable import MonAvi

/// Logica pura del catalogo de canje: puntos faltantes, orden, filtros,
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
        mapsUrl: String? = nil
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
            updatedAt: Date()
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

    // MARK: - Puntos faltantes

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

    private func redemptionJSON(status: String, expiresAt: String, withItem: Bool) -> String {
        let itemPart = withItem ? """
          ,"reward_items": {
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
        """ : ",\"reward_items\": null"
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
          "created_at": "2026-11-01T10:00:00Z"
          \(itemPart)
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
