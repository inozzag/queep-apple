import XCTest
#if os(macOS)
import AppKit
#endif

/// The basic operations on an uploaded image: rename, annotate, then delete from its document.
@MainActor
final class ImageEditTests: XCTestCase {
    func testEditTitleAndNotesThenDeleteImage() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Image fixtures use disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make(seed: false)
        let picture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-image", withExtension: "jpg"))
        try await fixture.uploadImage(picture)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        #if os(macOS)
        app.activate()
        #endif
        let card = app.buttons["Imagem"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        activate(card)
        let title = app.textFields["image.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        let save = app.buttons["image.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        enter("Quadro do workshop", into: title, app: app)
        enter("Ideias de onboarding anotadas na parede.", into: app.textViews["image.text"], app: app)
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "image-document"; shot.lifetime = .keepAlways; add(shot)
        activate(save)
        XCTAssertTrue(title.waitForNonExistence(timeout: 20), app.debugDescription)
        let renamed = app.buttons["Quadro do workshop"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 20), app.debugDescription)
        let saved = try await fixture.firstReference()
        XCTAssertEqual(saved?["title"] as? String, "Quadro do workshop")
        XCTAssertEqual(saved?["text"] as? String, "Ideias de onboarding anotadas na parede.")
        XCTAssertEqual(saved?["revision"] as? Int, 2)
        XCTAssertNotNil(saved?["image"])

        activate(renamed)
        XCTAssertTrue(app.textViews["image.text"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any).matching(identifier: "reference.more").firstMatch)
        let delete = app.descendants(matching: .any).matching(identifier: "image.delete").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        activate(delete)
        // The confirmation is a sheet on the Mac and an action sheet on iPhone; never the Touch Bar proxy.
        let confirm = app.sheets.buttons["Excluir"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        activate(confirm)
        XCTAssertTrue(renamed.waitForNonExistence(timeout: 20), app.debugDescription)
        let remaining = try await fixture.firstReference()
        XCTAssertNil(remaining)
        let status = try await fixture.delete()
        XCTAssertEqual(status, 202)
        #endif
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func enter(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        #if os(macOS)
        // XCTest key synthesis can drop letters with the host's keyboard layout; paste instead.
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
        #else
        field.tap()
        field.typeText(text)
        #endif
    }
}
