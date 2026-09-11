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
    #expect(page.items[0].source == nil)
}

@Test func decodesExtractedSourceWithoutReplacingUserTitleOrContext() throws {
    let raw = #"{"id":"link","kind":"link","title":"","text":"Meu contexto","url":"https://example.com","status":"ready","revision":1,"created_at":"2026-09-11T15:00:00Z","updated_at":"2026-09-11T15:00:00Z","source":{"state":"read","url":"https://example.com/page","title":"Título da página","text":"Conteúdo extraído","fetched_at":"2026-09-11T15:00:00Z","truncated":true,"limitations":["Trecho"]}}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.source?.text == "Conteúdo extraído")
    #expect(ref.source?.truncated == true)
    #expect(ref.displayTitle == "Título da página")
    #expect(ref.title.isEmpty && ref.text == "Meu contexto")
    let titled = raw.replacingOccurrences(of: #""title":"""#, with: #""title":"Minha referência""#)
    let custom = try APIClient.decoder().decode(Reference.self, from: Data(titled.utf8))
    #expect(custom.displayTitle == "Minha referência")
}
