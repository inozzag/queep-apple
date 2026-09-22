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
        account.click()
        XCTAssertTrue(app.buttons["account.usage"].waitForExistence(timeout: 10))
        app.buttons["account.usage"].click()
        XCTAssertTrue(app.staticTexts["usage.reset"].waitForExistence(timeout: 15))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["usage.reset"].waitForNonExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["capture.title"].waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["capture.title"].waitForNonExistence(timeout: 10))
        #endif
    }

    func testArchiveAndRestoreFromArchivedLibrary() async throws {
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
        let card = app.buttons[fixture.title]
        XCTAssertTrue(card.waitForExistence(timeout: 20), app.debugDescription)
        card.click()
        XCTAssertTrue(app.buttons["reference.more"].waitForExistence(timeout: 5))
        app.buttons["reference.more"].click()
        app.buttons["reference.archive"].click()
        XCTAssertTrue(card.waitForNonExistence(timeout: 10))

        app.buttons["library.archived"].click()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.click()
        app.buttons["reference.more"].click()
        app.buttons["reference.archive"].click()
        app.buttons["library.home"].click()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        #endif
    }
}
