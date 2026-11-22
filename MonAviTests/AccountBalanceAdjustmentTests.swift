import XCTest
@testable import MonAvi

final class AccountBalanceAdjustmentTests: XCTestCase {
    func testCreditCardStoresDebtAsNegative() {
        XCTAssertEqual(AccountBalanceAdjustment.storedBalance(entered: 412.35, type: .creditCard), -412.35)
        XCTAssertEqual(AccountBalanceAdjustment.storedBalance(entered: -50, type: .creditCard), -50)
    }

    func testOtherAccountsStoreWhatIsTyped() {
        XCTAssertEqual(AccountBalanceAdjustment.storedBalance(entered: 1245.30, type: .checking), 1245.30)
        XCTAssertEqual(AccountBalanceAdjustment.storedBalance(entered: 0, type: .savings), 0)
    }
}
