import Testing
import Foundation
@testable import QueepCore

@Test func refreshKeepsSearchHitsWhenRevisionChanges() throws {
    let processing = try waveReference(id: "a", status: "processing", revision: 1, title: "Velho")
    let ready = try waveReference(id: "a", status: "ready", revision: 4, title: "Novo")
    let untouched = try waveReference(id: "b", status: "queued", revision: 2, title: "Fora da página")
    let merged = SearchHits.updated([processing, untouched], with: [ready])
    #expect(merged.map(\.id) == ["a", "b"])
    #expect(merged[0].revision == 4)
    #expect(merged[0].status == "ready")
    #expect(merged[0].title == "Novo")
    #expect(merged[1].status == "queued")
    #expect(merged[1].revision == 2)

    let stillWorking = try waveReference(id: "a", status: "processing", revision: 9, title: "Atualizado")
    let kept = SearchHits.updated([processing], with: [stillWorking])
    #expect(kept.count == 1)
    #expect(kept[0].revision == 9)
    #expect(kept[0].status == "processing")
}

private func waveReference(id: String, status: String, revision: Int, title: String) throws -> Reference {
    let raw = """
    {"id":"\(id)","kind":"note","title":"\(title)","text":"","url":null,"status":"\(status)","revision":\(revision),"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z"}
    """
    return try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
}
