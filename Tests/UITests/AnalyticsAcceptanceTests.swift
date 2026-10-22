import XCTest

/// Drives a CloudDevelopment session: new account, one saved note, a search, logout, and sign-in again.
/// The note and the query are unique so a later check can confirm they never leave the device.
@MainActor
final class AnalyticsAcceptanceTests: XCTestCase {
    private var email = ""
    private var password = ""
    private var title = ""
    private var body = ""
    private var query = ""

    func testCloudAccountCaptureSearchAndSignOut() {
        let stamp = Int(Date().timeIntervalSince1970)
        email = "gaz121.\(stamp)@queepnotes.dev"
        password = "Queep-test-\(stamp)"
        title = "Nota gaz121 \(stamp)"
        body = "Frase secreta gaz121 \(stamp) que nao pode ir para o analytics."
        query = "consulta secreta gaz121 \(stamp)"
        try? "\(email)\n\(password)\n".write(toFile: "/tmp/queep-gaz121-account.txt", atomically: true, encoding: .utf8)

        let app = launch(create: true)
        let note = app.buttons["onboarding.capture.note"]
        let add = app.buttons["library.add"]
        let appeared = note.waitForExistence(timeout: 40) || add.waitForExistence(timeout: 5)
        XCTAssertTrue(appeared, app.debugDescription)
        if note.exists { note.tap() } else {
            add.tap()
            let noteRow = app.buttons["library.add.note"]
            XCTAssertTrue(noteRow.waitForExistence(timeout: 5), app.debugDescription)
            noteRow.tap()
        }

        let titleField = app.textFields["capture.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        type(title, into: titleField)
        type(body, into: app.textViews["capture.text"])
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.waitForExistence(timeout: 40), app.debugDescription)

        app.buttons["library.nav.search"].tap()
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        type(query + "\n", into: search)
        // The saved card uses a reference id as its identifier and the title as its label.
        let card = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        _ = card.waitForExistence(timeout: 50)

        if app.buttons["library.nav.back"].exists {
            app.buttons["library.nav.back"].tap()
        }
        app.buttons["person.crop.circle"].tap()
        let signOut = app.buttons["account.signout"]
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !signOut.exists {
            list.swipeUp()
        }
        XCTAssertTrue(signOut.waitForExistence(timeout: 3), app.debugDescription)
        signOut.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 15), app.debugDescription)

        let again = launch(create: false)
        XCTAssertTrue(again.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.waitForExistence(timeout: 40), again.debugDescription)
    }

    private func launch(create: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--ui-testing", "--ui-testing-cloud"]
        if create { arguments.append("--ui-testing-create") }
        app.launchArguments = arguments
        app.launchEnvironment = ["QUEEP_TEST_EMAIL": email, "QUEEP_TEST_PASSWORD": password]
        app.launch()
        return app
    }

    private func type(_ text: String, into element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        element.typeText(text)
    }
}
