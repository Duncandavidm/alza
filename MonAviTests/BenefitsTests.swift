import XCTest
@testable import MonAvi

/// Descuentos gratis de aliados "por ser de MonAvi" (migracion 0067):
/// decodificado de `my_benefits()`, estados del boton y textos.
final class BenefitsTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let itemId = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private let merchantId = "7F9619FF-8B86-D011-B42D-00C04FC964FF"

    private func benefitsJSON(unlocked: Bool, activeExpires: String?, againAt: String?, usedUp: Bool = false) -> String {
        let active = activeExpires.map { expires in
            """
            {
              "id": "8F9619FF-8B86-D011-B42D-00C04FC964FF",
              "user_id": "9F9619FF-8B86-D011-B42D-00C04FC964FF",
              "reward_item_id": "\(itemId)",
              "merchant_id": "\(merchantId)",
              "points_cost": 0,
              "code": "AB23CD",
              "status": "emitido",
              "expires_at": "\(expires)",
              "created_at": "2026-11-20T10:00:00Z",
              "source": "beneficio",
              "currency": "cashback"
            }
            """
        } ?? "null"
        return """
        {
          "unlocked": \(unlocked),
          "benefits": [
            {
              "item": {
                "id": "\(itemId)",
                "merchant_id": "\(merchantId)",
                "name": "20% de descuento",
                "description": "En toda la tienda",
                "photo_url": null,
                "points_cost": 0,
                "status": "active",
                "sort_order": 0,
                "reward_type": "porcentaje",
                "free_benefit": true,
                "per_user_limit": 1,
                "per_user_period": "semana",
                "max_redemptions": 50,
                "used_count": 47,
                "partner_merchants": {
                  "id": "\(merchantId)",
                  "name": "Café Duran",
                  "ruc": "155-1-2024",
                  "status": "active",
                  "logo_url": null,
                  "maps_url": null,
                  "category": "Cafés",
                  "address": "Calle 50",
                  "created_at": "2026-11-01T10:00:00Z",
                  "updated_at": "2026-11-01T10:00:00Z"
                }
              },
              "uses_in_period": \(againAt == nil ? 0 : 1),
              "available_again_at": \(againAt.map { "\"\($0)\"" } ?? "null"),
              "used_up": \(usedUp),
              "active_redemption": \(active)
            }
          ]
        }
        """
    }

    private func decode(_ json: String) throws -> BenefitsResponse {
        try decoder.decode(BenefitsResponse.self, from: Data(json.utf8))
    }

    private let now = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!

    func testDecodesBenefitWithMerchantAndLimit() throws {
        let response = try decode(benefitsJSON(unlocked: true, activeExpires: nil, againAt: nil))
        XCTAssertTrue(response.unlocked)
        let entry = try XCTUnwrap(response.benefits.first)
        XCTAssertTrue(entry.item.isFreeBenefit)
        XCTAssertEqual(entry.item.kind, .porcentaje)
        XCTAssertEqual(entry.item.merchantName, "Café Duran")
        XCTAssertEqual(entry.item.perUserPeriod, .semana)
        XCTAssertEqual(entry.item.remaining, 3)
        XCTAssertEqual(BenefitsMath.state(of: entry, unlocked: response.unlocked, now: now), .available)
        XCTAssertEqual(BenefitsMath.limitText(limit: entry.item.perUserLimit, period: entry.item.perUserPeriod), "1 vez por semana")
    }

    func testLockedUntilFirstInvoice() throws {
        let response = try decode(benefitsJSON(unlocked: false, activeExpires: nil, againAt: nil))
        let entry = try XCTUnwrap(response.benefits.first)
        XCTAssertEqual(BenefitsMath.state(of: entry, unlocked: response.unlocked, now: now), .locked)
        XCTAssertEqual(BenefitsMath.bestPercentText(response.benefits), "hasta 20%")
    }

    func testActiveCodeGetsItsProductAndCountsDown() throws {
        let response = try decode(benefitsJSON(unlocked: true, activeExpires: "2026-11-20T12:14:32Z", againAt: nil))
        let entry = try XCTUnwrap(response.benefits.first)
        guard case .active(let redemption) = BenefitsMath.state(of: entry, unlocked: true, now: now) else {
            return XCTFail("Debia tener un codigo vigente")
        }
        XCTAssertTrue(redemption.isBenefit)
        XCTAssertEqual(redemption.itemName, "20% de descuento")
        XCTAssertEqual(redemption.displayCostText, "Gratis")
        XCTAssertEqual(BenefitsMath.countdownText(until: redemption.expiresAt, now: now), "14:32")
        XCTAssertNil(BenefitsMath.countdownText(until: redemption.expiresAt, now: redemption.expiresAt))
    }

    func testExpiredCodeFallsBackToAvailable() throws {
        let response = try decode(benefitsJSON(unlocked: true, activeExpires: "2026-11-20T11:59:00Z", againAt: nil))
        let entry = try XCTUnwrap(response.benefits.first)
        XCTAssertEqual(BenefitsMath.state(of: entry, unlocked: true, now: now), .available)
    }

    func testCooldownAndUsedUp() throws {
        let again = "2026-11-23T05:00:00Z"
        let cooldown = try decode(benefitsJSON(unlocked: true, activeExpires: nil, againAt: again))
        let entry = try XCTUnwrap(cooldown.benefits.first)
        XCTAssertEqual(
            BenefitsMath.state(of: entry, unlocked: true, now: now),
            .cooldown(ISO8601DateFormatter().date(from: again)!)
        )

        let usedUp = try decode(benefitsJSON(unlocked: true, activeExpires: nil, againAt: nil, usedUp: true))
        XCTAssertEqual(BenefitsMath.state(of: try XCTUnwrap(usedUp.benefits.first), unlocked: true, now: now), .usedUp)
    }

    func testEmptyOrMalformedResponseIsEmpty() throws {
        let empty = try decode(#"{"unlocked": false, "benefits": []}"#)
        XCTAssertEqual(empty, .empty)
        let missing = try decode("{}")
        XCTAssertFalse(missing.unlocked)
        XCTAssertTrue(missing.benefits.isEmpty)
    }

    func testLimitTextsAndLeadingNumber() {
        XCTAssertEqual(BenefitsMath.limitText(limit: 2, period: .mes), "2 veces por mes")
        XCTAssertEqual(BenefitsMath.limitText(limit: nil, period: nil), "1 vez por semana")
        XCTAssertEqual(BenefitsMath.limitText(limit: 1, period: .siempre), "1 vez en total")
        XCTAssertEqual(RewardsMath.leadingNumber(in: "15% de descuento"), 15)
        XCTAssertNil(RewardsMath.leadingNumber(in: "Cupón de $20"))
    }

    func testUnknownPeriodAndSourceAreTolerated() throws {
        let json = #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "merchant_id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "10% de descuento", "points_cost": 0, "status": "active", "sort_order": 0, "free_benefit": true, "per_user_limit": 1, "per_user_period": "quincena"}"#
        let item = try decoder.decode(RewardItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.perUserPeriod, .semana)
    }

    func testHistoryHidesExpiredBenefitCodesOnly() throws {
        let response = try decode(benefitsJSON(unlocked: true, activeExpires: "2026-11-20T11:59:00Z", againAt: nil))
        let expiredBenefit = try XCTUnwrap(response.benefits.first?.activeRedemption)
        var delivered = expiredBenefit
        delivered.status = .entregado
        XCTAssertEqual(RewardsMath.historyRows([expiredBenefit, delivered], now: now).count, 1)
        XCTAssertEqual(delivered.statusText(now: now), "Aplicado")
    }
}
