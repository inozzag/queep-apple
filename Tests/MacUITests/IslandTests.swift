import XCTest

@MainActor
final class IslandTests: XCTestCase {
    /// The island stays hidden behind the notch, opens while the pointer rests on it and closes when it leaves.
    func testIslandOpensOnHoverAndClosesWhenLeaving() {
        let app = XCUIApplication()
        app.launch()
        let library = app.windows["library"]
        XCTAssertTrue(library.waitForExistence(timeout: 20))
        let handle = app.descendants(matching: .any).matching(identifier: "island").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10), app.debugDescription)
        snapshot("collapsed")
        handle.hover()
        let quick = app.buttons["island.quick"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["island.paste"].exists)
        XCTAssertTrue(app.buttons["island.screenshot"].exists)
        XCTAssertTrue(app.buttons["island.library"].exists)
        snapshot("expanded")
        library.hover()
        XCTAssertTrue(quick.waitForNonExistence(timeout: 5))
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        snapshot("collapsed-again")
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
