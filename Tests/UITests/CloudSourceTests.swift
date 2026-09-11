import XCTest

@MainActor
final class CloudSourceTests: XCTestCase {
    func testSearchAndReadExtractedPage() throws {
        // Opt-in QA: seed only the public HTTPX URL with this title in the existing
        // development account; remove that exact fixture through the API afterwards.
        let app = XCUIApplication()
        #if !QUEEP_CLOUD
        // Local QA uses the existing emulator-only preview fixture.
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = "preview@queep.test"
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = "queep-preview-only"
        #endif
        app.launch()
        let card = app.buttons["Teste Queep · leitura de link"]
        guard card.waitForExistence(timeout: 20) else {
            throw XCTSkip("Seed the disposable public HTTPX reference before this opt-in test.")
        }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("bibliotecas Python para HTTP assíncrono\n")
        XCTAssertTrue(app.staticTexts["Referências mais relevantes do seu acervo · até 10 por busca"]
            .waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(card.waitForExistence(timeout: 90), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.textFields["capture.url"].waitForExistence(timeout: 10))
        let expand = app.buttons["Ver texto lido"]
        for _ in 0..<5 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.waitForExistence(timeout: 15), app.debugDescription)
        expand.tap()
        let text = app.staticTexts["source.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text.label.contains("HTTPX"))
        XCTAssertTrue(text.label.contains("async"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Link encontrado por conteúdo e texto da página disponível"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
