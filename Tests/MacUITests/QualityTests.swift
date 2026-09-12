import XCTest

@MainActor
final class QualityTests: XCTestCase {
    func testUsageAndKeyboardCapture() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Disposable identities run only in emulators.")
        #else
        let fixture = try await DeletionFixture.make()
        addTeardownBlock { _ = try await fixture.delete() }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch(); app.activate()
        let account = app.descendants(matching: .any).matching(identifier: "person.crop.circle").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 20))
        account.click(); app.menuItems["account.usage"].click()
        XCTAssertTrue(app.staticTexts["usage.reset"].waitForExistence(timeout: 15))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["usage.reset"].waitForNonExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["capture.title"].waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["capture.title"].waitForNonExistence(timeout: 10))
        #endif
    }
}
