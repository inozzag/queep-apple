import XCTest
import AppKit

/// Opt-in visual QA on a signed-in library: reads and drafts only, never saves or searches.
@MainActor
final class RedesignSnapshotTests: XCTestCase {
    func testLibraryNoteAndDraftSnapshots() throws {
        guard ProcessInfo.processInfo.environment["QUEEP_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set QUEEP_SNAPSHOTS=1 to capture redesign screenshots on a signed-in library.")
        }
        let app = XCUIApplication()
        app.launch(); app.activate()
        let library = app.windows["library"]
        XCTAssertTrue(library.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 30), app.debugDescription)
        sleep(4)
        snap(library, "library")

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.click()
            paste("aquele quadro com ideias de interface", into: search, app: app)
            sleep(1)
            snap(library, "search-typing")
            let clear = app.buttons["Limpar"]
            if clear.waitForExistence(timeout: 3) { clear.click() } else { app.typeKey(.escape, modifierFlags: []) }
        }

        let cards = library.scrollViews.firstMatch.buttons
        var opened = false
        for index in 0..<min(cards.count, 6) where !opened {
            let card = cards.element(boundBy: index)
            guard card.exists, card.label != "Carregar mais" else { continue }
            card.click()
            if app.textViews["capture.text"].waitForExistence(timeout: 4) {
                sleep(3)
                snap(library, "note-detail")
                opened = true
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(app.textViews["capture.text"].waitForNonExistence(timeout: 5))
            } else if app.buttons["Fechar"].waitForExistence(timeout: 3) {
                sleep(2)
                snap(library, "detail-\(index)")
                app.buttons["Fechar"].firstMatch.click()
                XCTAssertTrue(app.buttons["Fechar"].waitForNonExistence(timeout: 5))
            }
        }

        app.buttons["library.add"].click()
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        paste("Ideias para o onboarding", into: app.textFields["capture.title"], app: app)
        paste("""
        # Primeira sessão
        Uma tela por vez, com **uma ação clara** e _texto curto_.

        - Mostrar o valor antes do login
        - [x] Revisar o texto do botão principal
        - [ ] Testar com três pessoas

        > Menos é mais quando a pessoa ainda não confia no app.

        Ver `Theme.swift` e [Craft](https://craft.do).
        """, into: editor, app: app)
        sleep(1)
        snap(library, "note-draft")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    private func snap(_ element: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "redesign-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func paste(_ text: String, into field: XCUIElement, app: XCUIApplication) {
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
