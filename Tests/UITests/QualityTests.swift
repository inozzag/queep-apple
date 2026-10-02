import XCTest

@MainActor
final class QualityTests: XCTestCase {
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            // iOS 26's scroll-edge fade reports contrast on text clipped by a viewport.
            // Audit the same content once scrolled into view; never ignore fully visible text.
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            let frame = element.frame
            if !app.frame.contains(frame) { return true }
            return app.scrollViews.allElementsBoundByIndex.contains { scroll in
                scroll.frame.intersects(frame) && !scroll.frame.contains(frame)
            }
        }
    }

    func testUsageAndCaptureWithLargestText() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Disposable identities run only in the emulators.")
        #else
        let fixture = try await DeletionFixture.make(seed: false)
        addTeardownBlock { _ = try await fixture.delete() }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 20))
        try audit(app)
        for _ in 0..<12 {
            if app.buttons["onboarding.capture.note"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["onboarding.capture.note"].isHittable)
        try audit(app)
        app.buttons["Conta"].tap()
        XCTAssertTrue(app.buttons["account.usage"].waitForExistence(timeout: 10))
        app.buttons["account.usage"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["usage.operations"].waitForExistence(timeout: 15))
        try audit(app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Uso com texto acessível máximo"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["usage.close"].tap()
        app.buttons["library.add"].tap()
        XCTAssertTrue(app.buttons["library.add.note"].waitForExistence(timeout: 5))
        app.buttons["library.add.note"].tap()
        XCTAssertTrue(app.textFields["capture.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls["capture.kind"].exists)
        try audit(app)
        app.buttons["Fechar"].tap()
        #endif
    }

    func testUsageAndLibraryWithDefaultText() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Disposable identities run only in the emulators.")
        #else
        let fixture = try await DeletionFixture.make()
        addTeardownBlock { _ = try await fixture.delete() }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
                               "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        XCTAssertTrue(app.buttons[fixture.title].waitForExistence(timeout: 20))
        try audit(app)
        app.buttons["Conta"].tap()
        XCTAssertTrue(app.buttons["account.usage"].waitForExistence(timeout: 10))
        app.buttons["account.usage"].tap()
        XCTAssertTrue(app.staticTexts["usage.reset"].waitForExistence(timeout: 15))
        try audit(app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Uso diário e privacidade"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["usage.close"].tap()
        app.buttons["library.add"].tap()
        XCTAssertTrue(app.buttons["library.add.note"].waitForExistence(timeout: 5))
        app.buttons["library.add.note"].tap()
        XCTAssertTrue(app.textFields["capture.title"].waitForExistence(timeout: 10))
        try audit(app)
        #endif
    }

    func testArchiveUndoAndArchivedLibrary() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Disposable identities run only in the emulators.")
        #else
        let fixture = try await DeletionFixture.make()
        addTeardownBlock { _ = try await fixture.delete() }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        let card = app.buttons[fixture.title]
        XCTAssertTrue(card.waitForExistence(timeout: 20), app.debugDescription)

        card.tap()
        XCTAssertTrue(app.buttons["reference.more"].waitForExistence(timeout: 5))
        app.buttons["reference.more"].tap()
        app.buttons["reference.archive"].tap()
        XCTAssertTrue(app.buttons["Desfazer"].waitForExistence(timeout: 5))
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        card.tap()
        app.buttons["reference.more"].tap()
        app.buttons["reference.archive"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 10))
        app.buttons["Conta"].tap()
        XCTAssertTrue(app.buttons["library.archived"].waitForExistence(timeout: 5))
        app.buttons["library.archived"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        app.buttons["reference.more"].tap()
        app.buttons["reference.archive"].tap()
        app.buttons["library.home"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        #endif
    }
}
