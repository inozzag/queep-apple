import XCTest

@MainActor
final class IslandTests: XCTestCase {
    /// The pin stays on screen. The card opens on click and closes on a second click, not when the pointer rests on it.
    func testIslandOpensOnClickAndClosesOnSecondClick() {
        let app = XCUIApplication()
        app.launch()
        let library = app.windows["library"]
        XCTAssertTrue(library.waitForExistence(timeout: 20))
        let handle = app.descendants(matching: .any).matching(identifier: "island").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10), app.debugDescription)
        snapshot("collapsed")
        handle.hover()
        let quick = app.buttons["island.quick"]
        XCTAssertFalse(quick.waitForExistence(timeout: 1), "Hover must not open the card")
        handle.click()
        XCTAssertTrue(quick.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["island.paste"].exists)
        XCTAssertTrue(app.buttons["island.screenshot"].exists)
        XCTAssertTrue(app.buttons["island.library"].exists)
        snapshot("expanded")
        handle.click()
        XCTAssertTrue(quick.waitForNonExistence(timeout: 5))
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        snapshot("collapsed-again")
        handle.click()
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        library.click()
        XCTAssertTrue(quick.waitForNonExistence(timeout: 5))
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        snapshot("collapsed-outside")
    }

    private func snapshot(_ name: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "island-\(name)-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
