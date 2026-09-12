import XCTest

@MainActor
final class FirstUseTests: XCTestCase {
    func testEmptyLibraryOffersDirectCaptureAndHelpRemainsAvailable() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("First-use fixtures run only in the emulators.")
        #else
        let fixture = try await DeletionFixture.make(seed: false)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["onboarding.capture.image"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Queep first use"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["onboarding.capture.link"].tap()
        XCTAssertTrue(app.textFields["capture.url"].waitForExistence(timeout: 10))
        app.buttons["Fechar"].tap()
        app.buttons["onboarding.capture.note"].tap()
        let title = app.textFields["capture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText(fixture.title)
        let editor = app.textViews["capture.text"]
        editor.tap(); editor.typeText("Minha primeira referência de interfaces de CRM.")
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["onboarding.title"].exists)
        app.buttons["Conta"].tap()
        app.buttons["account.help"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 10))
        app.buttons["onboarding.close"].tap()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 10))
        let cleanup = try await fixture.delete()
        XCTAssertEqual(cleanup, 202)
        #endif
    }
}
