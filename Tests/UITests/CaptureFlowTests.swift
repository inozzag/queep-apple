import XCTest

@MainActor
final class CaptureFlowTests: XCTestCase {
    func testSaveAndReopenNote() async throws {
        // Auth is a fixture for this capture test, avoiding OS password-manager dialogs.
        // The app obtains and refreshes a real Firebase emulator token through the SDK.
        let email = "preview@queep.test"
        let password = "queep-preview-only"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "returnSecureToken": true
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertTrue(status == 200 || String(decoding: data, as: UTF8.self).contains("EMAIL_EXISTS"))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = password
        app.launch()
        let add = app.buttons["library.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.tap()
        let title = app.textFields["capture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.tap()
        let noteTitle = "CRM branco \(UUID().uuidString.prefix(6))"
        title.typeText(noteTitle)
        let text = app.textViews["capture.text"]
        text.tap()
        text.typeText("Uma referência de interface com fundo branco e navegação lateral.")
        app.buttons["capture.save"].tap()
        let card = app.buttons[noteTitle]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.textViews["capture.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["capture.text"].value as? String,
                       "Uma referência de interface com fundo branco e navegação lateral.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Nota salva e recuperada"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }
}
