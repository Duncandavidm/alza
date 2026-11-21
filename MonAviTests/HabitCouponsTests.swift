import XCTest
@testable import MonAvi

/// Cupones por buenos habitos (migracion 0068): decodificado de
/// `my_habit_coupons()` y textos de progreso.
final class HabitCouponsTests: XCTestCase {
    private let json = """
    {
      "this_month": {
        "month": "2026-11", "income": 1500, "expenses": 1275.5, "savings_rate": 15,
        "logged_days": 9, "expense_count": 40, "budgets": 3, "budgets_met": 2,
        "receipts": 4, "overdue_bills": 0, "score": 61
      },
      "rules": [
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Ahorro 20%",
          "reason": "por ahorrar el 20% de tus ingresos en el mes", "rule_type": "ahorro_ingresos",
          "threshold": 20, "min_logged_days": 15, "coupon": "Cupón de $20", "merchant": "Bungla",
          "merchant_logo_url": null, "photo_url": null, "earned_count": 0
        },
        {
          "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Para todos",
          "reason": "por ser de MonAvi", "rule_type": "todos",
          "threshold": 0, "min_logged_days": 15, "coupon": "Cupón de $5", "merchant": "Café Duran",
          "merchant_logo_url": null, "photo_url": null, "earned_count": 1
        }
      ]
    }
    """

    private func decode() throws -> HabitCouponsResponse {
        try JSONDecoder().decode(HabitCouponsResponse.self, from: Data(json.utf8))
    }

    func testDecodesMonthAndRules() throws {
        let response = try decode()
        XCTAssertEqual(response.thisMonth?.savingsRate, 15)
        XCTAssertEqual(response.thisMonth?.budgetsMet, 2)
        XCTAssertEqual(response.rules.count, 2)
        XCTAssertEqual(response.rules.first?.merchant, "Bungla")
    }

    func testProgressTexts() throws {
        let response = try decode()
        let savings = response.rules[0]
        let everyone = response.rules[1]
        XCTAssertEqual(
            HabitCouponsMath.progressText(rule: savings, month: response.thisMonth),
            "Este mes vas en 15% de ahorro (meta 20%)."
        )
        XCTAssertEqual(
            HabitCouponsMath.loggedDaysHint(rule: savings, month: response.thisMonth),
            "Anota tus movimientos al menos 15 días del mes (llevas 9)."
        )
        XCTAssertNil(HabitCouponsMath.loggedDaysHint(rule: everyone, month: response.thisMonth))
        XCTAssertEqual(HabitCouponsMath.progressText(rule: everyone, month: response.thisMonth), "Ya está en Mis canjes con su código.")
        XCTAssertEqual(HabitCouponsMath.earnedText(1), "¡Ya lo ganaste!")
        XCTAssertEqual(HabitCouponsMath.earnedText(3), "Ganado 3 veces")
        XCTAssertNil(HabitCouponsMath.earnedText(0))
    }

    func testEmptyResponseIsTolerated() throws {
        let empty = try JSONDecoder().decode(HabitCouponsResponse.self, from: Data("{}".utf8))
        XCTAssertNil(empty.thisMonth)
        XCTAssertTrue(empty.rules.isEmpty)
    }

    func testReferralRewardTexts() {
        XCTAssertEqual(ReferralRewardCents.default.referrerText, Cashback.format(cents: 100))
        XCTAssertEqual(ReferralRewardCents(referrer: 250, referee: 0).referrerText, Cashback.format(cents: 250))
    }
}
