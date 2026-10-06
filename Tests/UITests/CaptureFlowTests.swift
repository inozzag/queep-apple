import XCTest

@MainActor
final class CaptureFlowTests: XCTestCase {
    private func authenticatedApp() async throws -> XCUIApplication {
        #if QUEEP_CLOUD
        throw XCTSkip("Capture fixtures run only against the local emulators.")
        #else
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
        return app
        #endif
    }

    func testSaveAndReopenNote() async throws {
        let app = try await authenticatedApp()
        let add = app.buttons["library.add"]
        add.tap()
        let note = app.buttons["library.add.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        note.tap()
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

    func testSignOutRevokesSharingAndSurvivesRelaunch() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("This test changes only the emulator account.")
        #else
        let app = try await authenticatedApp()
        app.buttons["Conta"].tap()
        app.buttons["Sair da conta"].tap()
        XCTAssertTrue(app.buttons["auth.emailStart"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.buttons["auth.emailStart"].waitForExistence(timeout: 10))
        // Open https://example.com in Safari on this simulator before running.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        safari.launch()
        let more = safari.buttons["MoreMenuButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        safari.buttons["ShareButton"].tap()
        safari.tapQueepShare()
        let notice = safari.staticTexts["Abra o Queep e entre na sua conta. Depois compartilhe novamente."]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), safari.debugDescription)
        XCTAssertFalse(safari.buttons["share.save"].isEnabled)
        safari.buttons["Fechar"].tap()
        #endif
    }
}
