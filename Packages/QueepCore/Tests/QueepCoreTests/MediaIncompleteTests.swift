import Testing
import Foundation
@testable import QueepCore

@Test func decodesMissingMediaIncompleteAsComplete() throws {
    let raw = #"{"id":"n","kind":"note","title":"Nota","text":"Oi","url":null,"status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z"}"#
    let reference = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(reference.mediaIncomplete != true)
    #expect(!reference.showsAnalysisRetry)
}

@Test func retriesReadyPostWhenMediaIsIncomplete() throws {
    let raw = #"{"id":"p","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":3,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","media_incomplete":true,"analysis":{"summary":"Post","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"partial","limitations":["A foto não chegou."]}}"#
    let reference = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(reference.mediaIncomplete == true)
    #expect(reference.showsAnalysisRetry)
    #expect(reference.analysis?.coverage == "partial")
    #expect(reference.analysis?.limitations == ["A foto não chegou."])
}

@Test func completeOrArchivedMediaDoesNotOfferRetry() throws {
    let complete = #"{"id":"c","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/2","status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","media_incomplete":false}"#
    let ready = try APIClient.decoder().decode(Reference.self, from: Data(complete.utf8))
    #expect(ready.mediaIncomplete == false)
    #expect(!ready.showsAnalysisRetry)

    let archived = #"{"id":"a","kind":"note","title":"Nota","text":"Oi","url":null,"status":"error","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","archived_at":"2026-09-20T16:00:00Z","media_incomplete":true}"#
    let stored = try APIClient.decoder().decode(Reference.self, from: Data(archived.utf8))
    #expect(!stored.showsAnalysisRetry)
}

@Test func pollStopsWhenReadyMediaIsIncomplete() {
    let policy = AnalysisPoll.Policy.post
    let waiting = AnalysisPoll.afterFetch(status: "ready", galleryEmpty: true, snapshot: .init(), policy: policy)
    #expect(waiting.1 == .keepPolling)
    let incomplete = AnalysisPoll.afterFetch(
        status: "ready", galleryEmpty: true, mediaIncomplete: true, snapshot: .init(), policy: policy
    )
    #expect(incomplete.1 == .stop)
}
