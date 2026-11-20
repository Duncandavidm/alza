import XCTest
@testable import MonAvi

/// Los puntos canjeables son centavos de cashback: 1 punto = US$0.01.
final class CashbackTests: XCTestCase {
    func testFormatsCentsAsDollars() {
        XCTAssertEqual(Cashback.format(cents: 0), "$0.00")
        XCTAssertEqual(Cashback.format(cents: 5), "$0.05")
        XCTAssertEqual(Cashback.format(cents: 84), "$0.84")
        XCTAssertEqual(Cashback.format(cents: 350), "$3.50")
        XCTAssertEqual(Cashback.format(cents: 100000), "$1,000.00")
    }
}
