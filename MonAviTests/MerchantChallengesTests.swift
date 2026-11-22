import XCTest
@testable import MonAvi

final class MerchantChallengesTests: XCTestCase {
    func testChallengeProgress() {
        let challenge = MerchantChallenge(title: "Escanea 3", merchant: "Café", coupon: "Café gratis", required: 3, confirmed: 1, pending: 1)
        XCTAssertEqual(MerchantChallengesText.challengeProgress(challenge), "1 de 3 facturas (+1 por confirmar)")
        let won = MerchantChallenge(title: "Escanea 3", merchant: "Café", coupon: "Café gratis", required: 3, confirmed: 3, won: true)
        XCTAssertEqual(MerchantChallengesText.challengeProgress(won), "¡Ganaste! Tu premio está en Mis canjes.")
        XCTAssertEqual(MerchantChallengesText.fraction(confirmed: 5, of: 3), 1)
    }

    func testDecodesServerJSON() throws {
        let list = #"[{"id":"7f1c1e7e-1111-4a4a-9b9b-222222222222","title":"Escanea 3 facturas","merchant":"Café","merchant_logo_url":null,"coupon":"Café gratis","photo_url":null,"required":3,"ends_at":"2026-12-01T04:59:59+00:00","confirmed":1,"pending":0,"won":false}]"#
        let challenges = try JSONDecoder().decode([MerchantChallenge].self, from: Data(list.utf8))
        XCTAssertEqual(challenges.first?.required, 3)
        XCTAssertNotNil(challenges.first?.endsAt)
    }
}
