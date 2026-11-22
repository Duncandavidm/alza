import XCTest
@testable import MonAvi

final class InvoiceGoalsTests: XCTestCase {
    func testProgressWithCoupon() {
        let goal = InvoiceGoal(confirmed: 8, pending: 2, goal: 15, coupon: "Cupón de $5", merchant: "Café La Esquina")
        XCTAssertEqual(InvoiceGoalsText.progress(goal), "Llevas 8 de 15 facturas este mes")
        XCTAssertEqual(InvoiceGoalsText.detail(goal), "Te faltan 7 facturas para ganar Cupón de $5 en Café La Esquina · 2 por confirmar")
        XCTAssertEqual(InvoiceGoalsText.fraction(confirmed: 8, of: 15), 8.0 / 15.0, accuracy: 0.0001)
    }

    func testGoalReachedAndEarned() {
        let reached = InvoiceGoal(confirmed: 15, pending: 0, goal: 15, coupon: "Café gratis")
        XCTAssertEqual(InvoiceGoalsText.progress(reached), "¡Llegaste a 15 facturas este mes!")
        XCTAssertEqual(InvoiceGoalsText.detail(reached), "Tu cupón llega mañana con un aviso.")
        let earned = InvoiceGoal(confirmed: 16, pending: 0, goal: 15, coupon: "Café gratis", merchant: "X", earned: true)
        XCTAssertEqual(InvoiceGoalsText.detail(earned), "Ganaste Café gratis en X: está en Mis canjes.")
        XCTAssertEqual(InvoiceGoalsText.fraction(confirmed: 20, of: 15), 1)
    }

    func testGoalWithoutCoupon() {
        let goal = InvoiceGoal(confirmed: 1, pending: 0, goal: 15)
        XCTAssertEqual(InvoiceGoalsText.detail(goal), "Cada factura suma cashback")
    }

    func testChallengeProgress() {
        let challenge = MerchantChallenge(title: "Escanea 3", merchant: "Café", coupon: "Café gratis", required: 3, confirmed: 1, pending: 1)
        XCTAssertEqual(InvoiceGoalsText.challengeProgress(challenge), "1 de 3 facturas (+1 por confirmar)")
        let won = MerchantChallenge(title: "Escanea 3", merchant: "Café", coupon: "Café gratis", required: 3, confirmed: 3, won: true)
        XCTAssertEqual(InvoiceGoalsText.challengeProgress(won), "¡Ganaste! Tu premio está en Mis canjes.")
    }

    func testDecodesServerJSON() throws {
        let json = #"{"confirmed":8,"pending":2,"goal":15,"coupon":null,"merchant":null,"image_url":null,"earned":false}"#
        let goal = try JSONDecoder().decode(InvoiceGoal.self, from: Data(json.utf8))
        XCTAssertEqual(goal, InvoiceGoal(confirmed: 8, pending: 2, goal: 15))

        let list = #"[{"id":"7f1c1e7e-1111-4a4a-9b9b-222222222222","title":"Escanea 3 facturas","merchant":"Café","merchant_logo_url":null,"coupon":"Café gratis","photo_url":null,"required":3,"ends_at":"2026-12-01T04:59:59+00:00","confirmed":1,"pending":0,"won":false}]"#
        let challenges = try JSONDecoder().decode([MerchantChallenge].self, from: Data(list.utf8))
        XCTAssertEqual(challenges.first?.required, 3)
        XCTAssertNotNil(challenges.first?.endsAt)
    }
}
