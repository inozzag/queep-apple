import XCTest
import AppKit

@MainActor
final class FirstUseTests: XCTestCase {
    func testFirstCaptureAndHelpOnMac() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("First-use fixtures run only in the emulators.")
        #else
        let fixture = try await DeletionFixture.make(seed: false)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 20))
        app.buttons["onboarding.capture.link"].click()
        XCTAssertTrue(app.textFields["capture.url"].waitForExistence(timeout: 10))
        app.buttons["Fechar"].click()
        XCTAssertTrue(app.textFields["capture.url"].waitForNonExistence(timeout: 10))
        app.buttons["onboarding.capture.note"].click()
        let title = app.textFields["capture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        paste(fixture.title, into: title, app: app)
        let editor = app.textViews["capture.text"]
        paste("Minha primeira referência no Mac.", into: editor, app: app)
        XCTAssertTrue(app.buttons["capture.save"].isEnabled)
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(title.waitForNonExistence(timeout: 15))
        let saved = try await fixture.containsSavedNote(text: "Minha primeira referência no Mac.")
        XCTAssertTrue(saved)
        let account = app.descendants(matching: .any).matching(identifier: "person.crop.circle").firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["onboarding.title"].exists)
        account.click(); app.menuItems["account.help"].click()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 10))
        app.buttons["onboarding.close"].click()
        let cleanup = try await fixture.delete()
        XCTAssertEqual(cleanup, 202)
        #endif
    }

    private func paste(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        // XCTest key synthesis can drop letters with the host's keyboard layout.
        // Exercise native paste and restore every original pasteboard representation.
        let board = NSPasteboard.general
        let original = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer { board.clearContents(); board.writeObjects(original) }
        field.click()
        board.clearContents(); board.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }
}
