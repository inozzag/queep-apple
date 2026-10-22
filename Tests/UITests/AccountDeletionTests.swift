import XCTest

@MainActor
final class AccountDeletionTests: XCTestCase {
    func testCancelWrongPasswordThenDeleteAndRejectOldSession() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Destructive test restricted to disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 20))
        openDeletion(app)
        XCTAssertFalse(app.buttons["account.delete.confirm"].isEnabled)
        app.buttons["account.delete.cancel"].tap()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 10))
        openDeletion(app)
        app.switches["account.delete.immediate"].tap()
        let password = app.secureTextFields["account.delete.password"]
        password.tap(); password.typeText("incorrect-password")
        app.buttons["account.delete.confirm"].tap()
        XCTAssertTrue(app.staticTexts["account.delete.error"].waitForExistence(timeout: 20))
        let before = try await fixture.libraryStatus()
        XCTAssertEqual(before, 200)
        password.tap(); password.typeText(fixture.password)
        app.buttons["account.delete.confirm"].tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 30), app.debugDescription)
        let notice = app.staticTexts["auth.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("Exclusão definitiva solicitada"))
        XCTAssertFalse(app.buttons[fixture.title].exists)
        let status = try await fixture.libraryStatus()
        XCTAssertEqual(status, 401)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Account deletion accepted and session cleared"
        shot.lifetime = .keepAlways
        add(shot)
        #endif
    }

    func testScheduledDeletionSurvivesLoginAndExplicitRecoveryPreservesNote() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Destructive test restricted to disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 20))
        openDeletion(app)
        let password = app.secureTextFields["account.delete.password"]
        password.tap(); password.typeText(fixture.password)
        app.buttons["account.delete.confirm"].tap()
        XCTAssertTrue(app.staticTexts["account.recovery.title"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["account.recovery.deadline"].exists)
        XCTAssertFalse(app.buttons[fixture.title].exists)
        let blocked = try await fixture.libraryStatus()
        XCTAssertEqual(blocked, 401)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["account.recovery.title"].waitForExistence(timeout: 20))
        let afterLogin = try await fixture.libraryStatus()
        XCTAssertEqual(afterLogin, 401)
        let recovery = app.secureTextFields["account.recovery.password"]
        recovery.tap(); recovery.typeText(fixture.password)
        app.buttons["account.recovery.restore"].tap()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 20))
        let restored = try await fixture.libraryStatus()
        XCTAssertEqual(restored, 200)
        let cleanup = try await fixture.delete()
        XCTAssertEqual(cleanup, 202)
        #endif
    }

    private func openDeletion(_ app: XCUIApplication) {
        app.buttons["Conta"].tap()
        XCTAssertTrue(app.buttons["account.delete"].waitForExistence(timeout: 10))
        app.buttons["account.delete"].tap()
        XCTAssertTrue(app.secureTextFields["account.delete.password"].waitForExistence(timeout: 10))
    }
}
