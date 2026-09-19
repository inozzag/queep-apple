import XCTest

/// Opt-in visual QA on a signed-in iPhone library: drafts only, never saves or searches.
@MainActor
final class RedesignSnapshotTests: XCTestCase {
    func testLibraryAndDraftSnapshots() throws {
        guard ProcessInfo.processInfo.environment["QUEEP_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set QUEEP_SNAPSHOTS=1 to capture redesign screenshots on a signed-in library.")
        }
        let app = XCUIApplication()
        app.launch()
        let add = app.buttons["library.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 30), app.debugDescription)
        sleep(4)
        snap(app, "ios-library")
        add.tap()
        let note = app.buttons["library.add.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        note.tap()
        let title = app.textFields["capture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        title.tap()
        title.typeText("Ideias para o onboarding")
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("# Primeira sessão\nUma tela por vez, com **uma ação clara**.\n\n- Mostrar o valor antes do login\n- [x] Revisar o botão\n- [ ] Testar com três pessoas\n\n> Menos é mais.")
        sleep(1)
        snap(app, "ios-note-draft")
        app.buttons["Fechar"].firstMatch.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "redesign-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
