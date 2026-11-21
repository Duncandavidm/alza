import XCTest
@testable import MonAvi

/// Sucursales de comercios (migracion 0076) y la mezcla de la lluvia de
/// billetes al canjear.
final class BranchesAndCelebrationTests: XCTestCase {
    private let json = """
    {
      "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
      "name": "Café La Esquina",
      "ruc": "155-1-2024",
      "status": "active",
      "logo_url": null,
      "maps_url": "https://maps.app.goo.gl/principal",
      "category": "Cafetería",
      "address": "Calle 50, Obarrio",
      "created_at": "2026-11-01T10:00:00Z",
      "updated_at": "2026-11-01T10:00:00Z",
      "merchant_branches": [
        {"id": "8F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "San Francisco", "address": "Vía Porras", "maps_url": null, "sort_order": 1},
        {"id": "9F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Costa del Este", "address": "Town Center", "maps_url": "https://maps.app.goo.gl/costa", "sort_order": 0}
      ]
    }
    """

    private func decode(_ text: String) throws -> PartnerMerchant {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PartnerMerchant.self, from: Data(text.utf8))
    }

    func testDecodesBranchesInPanelOrder() throws {
        let merchant = try decode(json)
        XCTAssertEqual(merchant.sortedBranches.map(\.name), ["Costa del Este", "San Francisco"])
        XCTAssertEqual(RewardsMath.branchesText(merchant), "y 2 sucursales más")
    }

    func testDirectionsOptionsListMainThenBranches() throws {
        let options = RewardsMath.directionsOptions(for: try decode(json))
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.first?.title, "Café La Esquina · Principal")
        XCTAssertEqual(options.first?.url.absoluteString, "https://maps.app.goo.gl/principal")
        XCTAssertEqual(options[1].url.absoluteString, "https://maps.app.goo.gl/costa")
        // Sin enlace propio: busqueda en Apple Maps con el nombre y la direccion.
        XCTAssertEqual(options[2].url.host, "maps.apple.com")
    }

    func testMerchantWithoutBranchesHasOneOption() throws {
        let single = json.replacingOccurrences(
            of: #"(?s),\s*"merchant_branches": \[.*\]"#,
            with: "",
            options: .regularExpression
        )
        let merchant = try decode(single)
        XCTAssertNil(RewardsMath.branchesText(merchant))
        let options = RewardsMath.directionsOptions(for: merchant)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Café La Esquina")
    }

    func testRainHasMoreBillsThanEmojis() {
        let pieces = MoneyRainView.makePieces(count: 50)
        let bills = pieces.filter { if case .bill = $0.kind { return true } else { return false } }.count
        XCTAssertEqual(bills, 30)
        XCTAssertGreaterThan(bills, pieces.count - bills)
        XCTAssertTrue(MoneyRainView.celebrationEmojis.contains("🎉"))
    }
}
