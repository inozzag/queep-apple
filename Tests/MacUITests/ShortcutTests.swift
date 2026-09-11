import XCTest

@MainActor
final class ShortcutTests: XCTestCase {
    func testCaptureShortcutWithLibraryClosed() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows["library"].waitForExistence(timeout: 20))
        app.typeKey("w", modifierFlags: .command)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey(" ", modifierFlags: [.command, .shift])
        let capture = app.dialogs["quickCapture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.textViews["quick.text"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(capture.exists)
    }
}
