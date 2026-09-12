import XCTest

@MainActor
final class MediaFlowTests: XCTestCase {
    func testSyncedAudioAndVideoOpenInNativePlayer() async throws {
        #if QUEEP_CLOUD
        throw XCTSkip("Media fixtures use disposable emulator accounts.")
        #else
        let fixture = try await DeletionFixture.make(seed: false)
        for (name, suffix) in [("sample-audio", "wav"), ("sample-video", "mp4")] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
            try await fixture.uploadMedia(url)
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["QUEEP_TEST_EMAIL"] = fixture.email
        app.launchEnvironment["QUEEP_TEST_PASSWORD"] = fixture.password
        app.launch()
        #if os(macOS)
        app.activate()
        #endif
        for title in ["Vídeo", "Áudio"] {
            let card = app.buttons[title]
            #if os(iOS)
            if !card.waitForExistence(timeout: 15) { app.swipeUp() }
            #endif
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            activate(card)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "media.player").firstMatch.waitForExistence(timeout: 20))
            activate(app.buttons["media.playPause"])
            let clock = app.staticTexts["media.elapsed"]
            let advanced = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@", "Tempo reproduzido: 0:00"), object: clock)
            await fulfillment(of: [advanced], timeout: 10)
            activate(app.buttons["media.playPause"])
            #if os(iOS)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Queep \(title) player"; shot.lifetime = .keepAlways; add(shot)
            #endif
            activate(app.buttons["Fechar"])
        }
        let status = try await fixture.delete()
        XCTAssertEqual(status, 202)
        #endif
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
}
