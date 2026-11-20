import XCTest
@testable import MonAvi

@MainActor
final class NotificationRouterTests: XCTestCase {
    func testPointsScreenOpensPoints() {
        let router = NotificationRouter()
        router.open(screen: "points")
        XCTAssertEqual(router.destination, .points)
    }

    func testUnknownOrMissingScreenDoesNothing() {
        let router = NotificationRouter()
        router.open(screen: nil)
        XCTAssertNil(router.destination)
        router.open(screen: "otra-cosa")
        XCTAssertNil(router.destination)
    }

    func testRedemptionsScreenOpensMyRedemptions() {
        let router = NotificationRouter()
        router.open(screen: "redemptions")
        XCTAssertEqual(router.destination, .redemptions)
    }

    func testHomeScreenClearsAnyOpenDestination() {
        let router = NotificationRouter()
        router.open(screen: "rewards")
        XCTAssertEqual(router.destination, .rewards)
        router.open(screen: "home")
        XCTAssertNil(router.destination)
    }
}
