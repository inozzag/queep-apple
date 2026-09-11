import XCTest

@MainActor
final class CloudSearchTests: XCTestCase {
    func testSearchAcrossDevices() throws {
        #if QUEEP_CLOUD
        // Manual cloud QA: sign in normally and create this synthetic note on the Mac first.
        // Keeps the existing account/session; no credentials or personal contents in fixtures.
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons["Teste Queep · material esportivo"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("calçados para jogar em quadra de saibro\n")
        XCTAssertTrue(app.staticTexts["Referências mais relevantes do seu acervo · até 10 por busca"]
            .waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(card.exists)
        card.tap()
        let note = app.textViews["capture.text"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue((note.value as? String)?.contains("solado em espinha de peixe") == true)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Busca semântica recupera a nota criada no Mac"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #else
        throw XCTSkip("Cloud search QA is opt-in through CloudDevelopment and a synthetic Mac note.")
        #endif
    }
}
