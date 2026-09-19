import XCTest

@MainActor
final class RevenueCatCrossDeviceTests: XCTestCase {
    func testPurchaseFromIPhoneIsActiveOnMac() throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Requires the dedicated local RevenueCat fixture.")
        #else
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/revenuecat-test-account.json")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Run the iPhone Test Store purchase first.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = "preview@queep.test"
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = "queep-preview-only"
        app.launch()
        let account = app.descendants(matching: .any).matching(identifier: "person.crop.circle").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 20), app.debugDescription)
        account.click()
        XCTAssertTrue(app.buttons["account.subscription"].waitForExistence(timeout: 10))
        app.buttons["account.subscription"].click()
        let status = app.staticTexts["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), app.debugDescription)
        let active = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Assinatura ativa"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 30), .completed, app.debugDescription)
        let restore = app.buttons["subscription.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 20))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: restore)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        restore.click()
        let message = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "Sua assinatura está ativa nesta conta.")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["subscription.close"].click()
        #endif
    }
}
