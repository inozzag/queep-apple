import XCTest

@MainActor
final class RevenueCatTests: XCTestCase {
    func testExistingTestStoreAccessAfterLocalAppReinstall() throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Requires the dedicated local RevenueCat fixture.")
        #else
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/revenuecat-test-account.json")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Run the Test Store purchase first, while its subscription is active.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = "preview@queep.test"
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = "queep-preview-only"
        app.launch()
        openSubscription(app)
        let status = app.staticTexts["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), app.debugDescription)
        let active = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Assinatura ativa"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 30), .completed, app.debugDescription)
        app.buttons["subscription.restore"].tap()
        XCTAssertTrue(app.staticTexts["Sua assinatura está ativa nesta conta."].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["subscription.close"].tap()
        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 5))
        #endif
    }

    func testRealTestStoreCancellationFailurePurchaseAndRestore() throws {
        #if QUEEP_CLOUD
        throw XCTSkip("This opt-in test runs only against the local Firebase account.")
        #else
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/revenuecat-test-account.json")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Configure the dedicated RevenueCat Test Store fixture first.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = "preview@queep.test"
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = "queep-preview-only"
        app.launch()
        openSubscription(app)
        let status = app.staticTexts["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(status.label.contains("Sem assinatura ativa"), app.debugDescription)
        let buy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "subscription.buy.")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 30), app.debugDescription)
        let offer = XCTAttachment(screenshot: app.screenshot())
        offer.name = "RevenueCat Test Store plans before purchase"; offer.lifetime = .keepAlways
        add(offer)
        // The SDK alert is the safety gate: never confirm an Apple payment sheet here.
        buy.tap()
        let dialog = app.alerts["Test Store Purchase"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), app.debugDescription)
        dialog.buttons["Cancel"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        buy.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        dialog.buttons["Test failed purchase"].tap()
        XCTAssertTrue(app.staticTexts["subscription.error"].waitForExistence(timeout: 20))
        buy.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        dialog.buttons["Test valid purchase"].tap()
        let active = NSPredicate(format: "label CONTAINS %@", "Assinatura ativa")
        for _ in 0..<6 {
            if active.evaluate(with: status) { break }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: active, object: status)], timeout: 4)
            if !active.evaluate(with: status) && app.buttons["subscription.refresh"].isEnabled {
                app.buttons["subscription.refresh"].tap()
            }
        }
        XCTAssertTrue(active.evaluate(with: status), app.debugDescription)
        app.buttons["subscription.restore"].tap()
        XCTAssertTrue(app.staticTexts["Sua assinatura está ativa nesta conta."].waitForExistence(timeout: 30), app.debugDescription)
        let confirmed = XCTAttachment(screenshot: app.screenshot())
        confirmed.name = "RevenueCat purchase and restore confirmed by API"; confirmed.lifetime = .keepAlways
        add(confirmed)
        app.terminate()
        app.launch()
        openSubscription(app)
        XCTAssertTrue(status.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(active.evaluate(with: status))
        #endif
    }

    private func openSubscription(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Conta"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Conta"].tap()
        XCTAssertTrue(app.buttons["account.subscription"].waitForExistence(timeout: 10))
        app.buttons["account.subscription"].tap()
    }
}
