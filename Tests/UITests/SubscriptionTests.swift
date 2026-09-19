import XCTest

@MainActor
final class SubscriptionTests: XCTestCase {
    func testDevelopmentAccessCanBeReviewedWithoutBlockingLibrary() throws {
        let app = XCUIApplication()
        #if !QUEEP_CLOUD
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = "preview@queep.test"
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = "queep-preview-only"
        #endif
        app.launch()
        let account = app.buttons["Conta"]
        XCTAssertTrue(account.waitForExistence(timeout: 20), app.debugDescription)
        account.tap()
        XCTAssertTrue(app.buttons["account.subscription"].waitForExistence(timeout: 10))
        app.buttons["account.subscription"].tap()
        let status = app.staticTexts["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(status.label.contains("Acesso de desenvolvimento"))
        app.buttons["subscription.refresh"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Assinatura nativa no ambiente de desenvolvimento"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["subscription.close"].tap()
        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 5))
    }
}
