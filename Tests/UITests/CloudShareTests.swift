import XCTest

@MainActor
final class CloudShareTests: XCTestCase {
    func testSharePhotoUsingExistingAccount() throws {
        #if QUEEP_CLOUD
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 20))
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        let grid = photos.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(grid.firstMatch.waitForExistence(timeout: 10))
        // Import evaluation/fixtures/001.png last into this simulator before running.
        grid.element(boundBy: grid.count - 1).tap()
        let share = photos.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), photos.debugDescription)
        share.tap()
        let queep = photos.cells["Queep"]
        XCTAssertTrue(queep.waitForExistence(timeout: 10), photos.debugDescription)
        queep.tap()
        let save = photos.buttons["share.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), photos.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, photos.debugDescription)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 30), photos.debugDescription)
        app.activate()
        let card = app.buttons["Imagem"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.textFields["image.title"].waitForExistence(timeout: 10))
        app.buttons["reference.more"].tap()
        XCTAssertTrue(app.buttons["image.delete"].waitForExistence(timeout: 10))
        #else
        throw XCTSkip("Requires CloudDevelopment and a synthetic photo imported to the simulator.")
        #endif
    }

    func testShareSafariLinkUsingExistingAccount() throws {
        #if QUEEP_CLOUD
        // Opt-in QA on the cloud simulator, already signed in. No credential fixture.
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 20))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        safari.launch()
        let more = safari.buttons["MoreMenuButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        safari.buttons["ShareButton"].tap()
        let queep = safari.cells["Queep"]
        XCTAssertTrue(queep.waitForExistence(timeout: 10), safari.debugDescription)
        queep.tap()
        let save = safari.buttons["share.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), safari.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, safari.debugDescription)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 30), safari.debugDescription)
        app.activate()
        let card = app.buttons["example.com"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.textFields["capture.url"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textFields["capture.url"].value as? String)?.contains("queep-native-share") == true)
        #else
        throw XCTSkip("Requires CloudDevelopment and an existing test account.")
        #endif
    }
}
