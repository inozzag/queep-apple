import XCTest
#if os(macOS)
import AppKit
#endif

@MainActor
extension XCTestCase {
    func runSpacesJourney() async throws {
        continueAfterFailure = false
        #if QUEEP_CLOUD
        throw XCTSkip("Spaces uses disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make()
        let savedReference = try await fixture.firstReference()
        let referenceID = try XCTUnwrap(savedReference?["id"] as? String)
        let name = "Moodboard \(UUID().uuidString.prefix(6))"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        #if os(macOS)
        app.activate()
        #endif
        XCTAssertTrue(app.buttons["library.spaces"].waitForExistence(timeout: 25))
        activateSpaceElement(app.buttons["library.spaces"])
        XCTAssertTrue(app.buttons["spaces.new"].waitForExistence(timeout: 10))
        activateSpaceElement(app.buttons["spaces.new"])
        let field = app.textFields["spaces.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        activateSpaceElement(field)
        #if os(macOS)
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        board.clearContents(); board.setString(name, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        board.clearContents(); board.writeObjects(saved)
        #else
        field.typeText(name)
        #endif
        activateSpaceElement(app.buttons["spaces.save"])
        XCTAssertTrue(field.waitForNonExistence(timeout: 15))
        let (data, status) = try await DeletionFixture.send("http://127.0.0.1:8000/v1/spaces", method: "GET", token: fixture.token)
        XCTAssertEqual(status, 200)
        let spaces = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let id = try XCTUnwrap(spaces.first { $0["name"] as? String == name }?["id"] as? String)
        activateSpaceElement(app.buttons["spaces.all"])
        let card = app.buttons["reference.\(referenceID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        activateSpaceElement(card)
        XCTAssertTrue(app.buttons["reference.space"].waitForExistence(timeout: 10))
        activateSpaceElement(app.buttons["reference.space"])
        let choice = app.buttons["spaces.pick.\(id)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        activateSpaceElement(choice)
        let selected = NSPredicate(format: "value == %@", "Selecionado")
        await fulfillment(of: [expectationsForSpaceSelection(selected, choice)], timeout: 10)
        XCTAssertTrue(app.buttons["spaces.done"].waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "enabled == true")
        let done = app.buttons["spaces.done"]
        let ready = XCTNSPredicateExpectation(predicate: enabled, object: done)
        await fulfillment(of: [ready], timeout: 10)
        activateSpaceElement(done)
        activateSpaceElement(app.buttons["Fechar"])
        let tab = app.buttons["spaces.tab.\(id)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        activateSpaceElement(tab)
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let (pageData, pageStatus) = try await DeletionFixture.send("http://127.0.0.1:8000/v1/references?space_id=\(id)", method: "GET", token: fixture.token)
        XCTAssertEqual(pageStatus, 200)
        let page = try JSONSerialization.jsonObject(with: pageData) as! [String: Any]
        XCTAssertEqual((page["items"] as? [[String: Any]])?.count, 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Spaces — criar, atribuir e filtrar"
        shot.lifetime = .keepAlways
        add(shot)
        let cleanup = try await fixture.delete()
        XCTAssertEqual(cleanup, 202)
        #endif
    }

    private func expectationsForSpaceSelection(_ predicate: NSPredicate, _ element: XCUIElement) -> XCTestExpectation {
        XCTNSPredicateExpectation(predicate: predicate, object: element)
    }

    private func activateSpaceElement(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
}
