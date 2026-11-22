import XCTest
@testable import MonAvi

final class CreditCardMathTests: XCTestCase {
    func testAvailableAndUtilization() {
        XCTAssertEqual(CreditCardMath.available(limit: 2000, used: 600), 1400)
        XCTAssertEqual(CreditCardMath.utilization(limit: 2000, used: 600) ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(CreditCardMath.summary(limit: 2000, used: 600), "Disponible $1,400 · usas el 30% del cupo")
        XCTAssertNil(CreditCardMath.summary(limit: nil, used: 600))
        XCTAssertEqual(CreditCardMath.summary(limit: 500, used: 650), "Te pasaste del cupo por $150")
    }

    func testRateConversion() {
        XCTAssertEqual(CreditCardMath.monthlyRate("24", period: .annual), 2)
        XCTAssertEqual(CreditCardMath.monthlyRate("2", period: .monthly), 2)
        XCTAssertEqual(CreditCardMath.monthlyRate("18%", period: .annual), 1.5)
        XCTAssertEqual(CreditCardMath.annualRate(monthly: 2), 24)
        XCTAssertEqual(CreditCardMath.rateText(monthly: 2), "2% al mes (24% al año)")
        XCTAssertNil(CreditCardMath.monthlyRate("", period: .annual))
    }

    func testZeroIsAllowed() {
        XCTAssertEqual(CreditCardMath.parse("0"), 0)
        XCTAssertEqual(CreditCardMath.parse("1,250.50"), 1250.5)
    }
}
