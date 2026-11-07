import XCTest
@testable import MonAvi

/// Logica pura de "Ofertas de marcas" (textos del bono, filtro/orden,
/// decodificado tolerante) y del aviso de pago con tarjeta en un
/// comercio aliado (coincidencia de nombres, identificador por dia).
final class BrandCampaignTests: XCTestCase {
    // MARK: - Texto del bono

    func testPerUnitPoints() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .puntos, perUnit: 10, percent: nil), "+10 pts por unidad")
    }

    func testPerUnitCashbackCents() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .cashback, perUnit: 25, percent: nil), "+25¢ por unidad")
    }

    func testPerUnitWinsOverPercent() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .puntos, perUnit: 5, percent: 2), "+5 pts por unidad")
    }

    func testDoubleCashback() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .cashback, perUnit: nil, percent: 1), "Doble cashback")
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .cashback, perUnit: 0, percent: 1.0), "Doble cashback")
    }

    func testPercentCashback() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .cashback, perUnit: nil, percent: 2), "+2¢ por cada $1")
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .cashback, perUnit: nil, percent: 1.5), "+1.5¢ por cada $1")
    }

    func testPercentPoints() {
        XCTAssertEqual(BrandCampaignText.bonusText(currency: .puntos, perUnit: nil, percent: 1), "+1 pts por cada $1")
    }

    func testNoBonus() {
        XCTAssertNil(BrandCampaignText.bonusText(currency: .cashback, perUnit: nil, percent: nil))
        XCTAssertNil(BrandCampaignText.bonusText(currency: .puntos, perUnit: 0, percent: 0))
    }

    func testUnitsLimitText() {
        XCTAssertEqual(BrandCampaignText.unitsLimitText(3), "Hasta 3 unidades por factura")
        XCTAssertEqual(BrandCampaignText.unitsLimitText(1), "Hasta 1 unidad por factura")
        XCTAssertNil(BrandCampaignText.unitsLimitText(nil))
        XCTAssertNil(BrandCampaignText.unitsLimitText(0))
    }

    func testNumberFormatting() {
        XCTAssertEqual(BrandCampaignText.number(2), "2")
        XCTAssertEqual(BrandCampaignText.number(1.5), "1.5")
        XCTAssertEqual(BrandCampaignText.number(0.25), "0.25")
    }

    // MARK: - Filtro y orden

    func testCurrentFiltersByDatesAndSortsByEnd() {
        let now = Date()
        let day: TimeInterval = 86_400
        let expired = BrandCampaign(brand: "Vieja", name: "", bonusCurrency: .cashback, endsAt: now.addingTimeInterval(-day))
        let future = BrandCampaign(brand: "Futura", name: "", bonusCurrency: .cashback, startsAt: now.addingTimeInterval(day))
        let late = BrandCampaign(brand: "Tarde", name: "", bonusCurrency: .cashback, endsAt: now.addingTimeInterval(10 * day))
        let soon = BrandCampaign(brand: "Pronto", name: "", bonusCurrency: .cashback, endsAt: now.addingTimeInterval(day))
        let open = BrandCampaign(brand: "Abierta", name: "", bonusCurrency: .cashback)

        let result = BrandCampaignsRepository.current([expired, future, open, late, soon], now: now)
        XCTAssertEqual(result.map(\.brand), ["Pronto", "Tarde", "Abierta"])
    }

    // MARK: - Decodificado

    func testDecodesTolerantly() throws {
        let json = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "brand": "Coca-Cola",
          "name": "Verano",
          "description": "Compra Coca-Cola 2L",
          "image_url": null,
          "merchant_rucs": ["155-1-2024"],
          "bonus_currency": "puntos",
          "bonus_per_unit": 10,
          "bonus_percent": null,
          "max_units_per_receipt": 3,
          "starts_at": "2026-11-01T00:00:00+00:00",
          "ends_at": "2026-11-30",
          "status": "active"
        }
        """
        let campaign = try JSONDecoder().decode(BrandCampaign.self, from: Data(json.utf8))
        XCTAssertEqual(campaign.brand, "Coca-Cola")
        XCTAssertEqual(campaign.bonusCurrency, .puntos)
        XCTAssertEqual(campaign.bonusPerUnit, 10)
        XCTAssertNil(campaign.bonusPercent)
        XCTAssertEqual(campaign.maxUnitsPerReceipt, 3)
        XCTAssertEqual(campaign.merchantRucs, ["155-1-2024"])
        XCTAssertNotNil(campaign.startsAt)
        XCTAssertNotNil(campaign.endsAt)
        XCTAssertEqual(BrandCampaignText.bonusText(for: campaign), "+10 pts por unidad")
    }

    func testDecodesNumericAsString() throws {
        let json = """
        {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "brand": "Nestlé", "name": "x",
         "bonus_currency": "cashback", "bonus_percent": "1", "status": "active"}
        """
        let campaign = try JSONDecoder().decode(BrandCampaign.self, from: Data(json.utf8))
        XCTAssertEqual(campaign.bonusPercent, 1)
        XCTAssertEqual(BrandCampaignText.bonusText(for: campaign), "Doble cashback")
    }

    // MARK: - Comercio aliado (Atajos)

    func testPartnerMatchIgnoresCaseAndAccents() {
        let partners = ["Super 99", "Farmacias Arrocha", "Café Unido"]
        XCTAssertEqual(PartnerMerchantMatcher.match(merchant: "SUPER 99 VIA ESPAÑA", partnerNames: partners), "Super 99")
        XCTAssertEqual(PartnerMerchantMatcher.match(merchant: "cafe unido costa del este", partnerNames: partners), "Café Unido")
        XCTAssertEqual(PartnerMerchantMatcher.match(merchant: "ARROCHA", partnerNames: partners), "Farmacias Arrocha")
        XCTAssertNil(PartnerMerchantMatcher.match(merchant: "Riba Smith", partnerNames: partners))
    }

    func testPartnerMatchSkipsTooShortNames() {
        XCTAssertNil(PartnerMerchantMatcher.match(merchant: "ab", partnerNames: ["ab"]))
        XCTAssertNil(PartnerMerchantMatcher.match(merchant: "Rey Panama", partnerNames: ["R"]))
    }

    func testPartnerHintIdIsPerMerchantAndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Panama")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 15))!
        let id = NotificationManager.partnerCardHintId(merchant: "Café Unido", date: date, calendar: calendar)
        XCTAssertEqual(id, "partner-card-cafe unido-2026-11-07")
        XCTAssertEqual(id, NotificationManager.partnerCardHintId(merchant: "CAFE UNIDO", date: date, calendar: calendar))
    }
}
