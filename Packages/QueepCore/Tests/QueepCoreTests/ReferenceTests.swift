import Testing
import Foundation
@testable import QueepCore

@Test func captureValidationPreventsUnsafeLinksAndEmptyNotes() {
    #expect(!Capture(kind: "note", title: "", text: "  \n ").isValid)
    #expect(!Capture(kind: "link", title: "", text: "", url: "javascript:alert(1)").isValid)
    #expect(!Capture(kind: "link", title: "", text: "", url: "https://u:secret@example.com").isValid)
    #expect(Capture(kind: "link", title: "", text: "", url: "https://github.com").isValid)
    #expect(Capture(kind: "note", title: "", text: "CRM com fundo branco").isValid)
    #expect(!Capture(kind: "note", title: "", text: String(repeating: "a", count: 30_001)).isValid)
}

@Test func decodesBackendDatesAndPartialAnalysis() throws {
    let json = #"{"items":[{"id":"123","kind":"link","title":"","text":"","url":"https://github.com","status":"ready","revision":2,"created_at":"2026-09-10T15:00:00.123456+00:00","updated_at":"2026-09-10T15:00:00Z","analysis":{"summary":"Repository","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"partial","limitations":["Only title available"]}}],"next_cursor":"cursor"}"#
    let page = try APIClient.decoder().decode(LibraryPage.self, from: Data(json.utf8))
    #expect(page.items.count == 1)
    #expect(page.nextCursor == "cursor")
    #expect(page.items[0].displayTitle == "github.com")
    #expect(page.items[0].statusLabel == "Análise parcial")
    #expect(page.items[0].analysis?.limitations == ["Only title available"])
}
