import XCTest

@MainActor
final class AccountDeletionTests: XCTestCase {
    func testDeletionFromAnotherClientClearsMacLibraryAndSheet() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Destructive test restricted to disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        let account = app.descendants(matching: .any).matching(identifier: "person.crop.circle").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 20))
        account.click()
        app.menuItems["account.delete"].click()
        XCTAssertTrue(app.secureTextFields["account.delete.password"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["account.delete.confirm"].isEnabled)
        let deleted = try await fixture.delete(immediate: false)
        XCTAssertEqual(deleted, 202)
        XCTAssertTrue(app.staticTexts["account.recovery.title"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons[fixture.title].exists)
        XCTAssertFalse(app.secureTextFields["account.delete.password"].exists)
        let password = app.secureTextFields["account.recovery.password"]
        password.click(); password.typeText(fixture.password)
        app.buttons["account.recovery.restore"].click()
        XCTAssertTrue(account.waitForExistence(timeout: 20))
        let restored = try await fixture.libraryStatus()
        XCTAssertEqual(restored, 200)
        let cleanup = try await fixture.delete()
        XCTAssertEqual(cleanup, 202)
        #endif
    }
}
