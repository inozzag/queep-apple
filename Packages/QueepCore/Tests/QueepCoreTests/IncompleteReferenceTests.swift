import Testing
import Foundation
@testable import QueepCore

private let created = #""created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z""#
private let picture = #""image":{"sha256":"aa","content_type":"image/jpeg","width":10,"height":10,"byte_count":1}"#
private let full = #""analysis":{"summary":"Uma leitura","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]}"#

private func reference(_ fields: String) throws -> Reference {
    try APIClient.decoder().decode(Reference.self, from: Data("{\(fields)}".utf8))
}

@Test func incompleteDoesNotRequireMediaIncompleteFlag() throws {
    let emptyPost = try reference(#""id":"p","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":1,\#(created),"analysis":{"summary":"Só o texto","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]}"#)
    #expect(emptyPost.mediaIncomplete == nil)
    #expect(emptyPost.isSocialPost)
    #expect(emptyPost.isIncomplete)
    #expect(emptyPost.galleryStatusLine == "A foto ou o clipe não chegou.")
    #expect(emptyPost.showsAnalysisRetry)

    let flaggedFalse = try reference(#""id":"f","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":1,\#(created),"media_incomplete":false,"analysis":{"summary":"Só o texto","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]}"#)
    #expect(flaggedFalse.mediaIncomplete == false)
    #expect(flaggedFalse.isIncomplete)
}

@Test func picturedSocialPostAndNotesAreComplete() throws {
    let post = try reference(#""id":"p","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":1,\#(created),\#(full),\#(picture)"#)
    #expect(!post.isIncomplete)
    #expect(post.galleryStatusLine == nil)
    #expect(!post.showsAnalysisRetry)

    let note = try reference(#""id":"n","kind":"note","title":"Nota","text":"Uma nota","url":null,"status":"ready","revision":1,\#(created)"#)
    #expect(!note.expectsPicture)
    #expect(!note.isIncomplete)
    #expect(note.galleryStatusLine == nil)

    let audio = try reference(#""id":"a","kind":"audio","title":"Áudio","text":"","url":null,"status":"ready","revision":1,\#(created)"#)
    #expect(!audio.isIncomplete)
}

@Test func missingPictureOnImageVideoAndWebsiteIsIncomplete() throws {
    let image = try reference(#""id":"i","kind":"image","title":"Foto","text":"","url":null,"status":"ready","revision":1,\#(created)"#)
    #expect(image.isIncomplete)
    #expect(image.galleryStatusLine == "A foto ou o clipe não chegou.")

    let video = try reference(#""id":"v","kind":"video","title":"Clipe","text":"","url":null,"status":"ready","revision":1,\#(created)"#)
    #expect(video.isIncomplete)

    let site = try reference(#""id":"s","kind":"link","title":"","text":"","url":"https://cursor.com/blog","status":"ready","revision":1,\#(created),"analysis":{"summary":"Um artigo","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]}"#)
    #expect(site.isWebsite)
    #expect(site.isIncomplete)

    let withFile = try reference(#""id":"m","kind":"video","title":"Clipe","text":"","url":null,"status":"ready","revision":1,\#(created),"media":{"sha256":"bb","content_type":"video/mp4","duration_seconds":4,"byte_count":20,"has_audio":false,"width":100,"height":80,"loop":true}"#)
    #expect(withFile.gallery.isEmpty)
    #expect(withFile.media != nil)
    #expect(!withFile.isIncomplete)
}

@Test func partialCoverageAndURLOnlySummaryAreIncomplete() throws {
    let partial = try reference(#""id":"n","kind":"note","title":"Nota","text":"Texto","url":null,"status":"ready","revision":1,\#(created),"analysis":{"summary":"Quase","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"partial","limitations":[]}"#)
    #expect(partial.isIncomplete)
    #expect(partial.galleryStatusLine == "Análise parcial")

    let limited = try reference(#""id":"n","kind":"note","title":"Nota","text":"Texto","url":null,"status":"ready","revision":1,\#(created),"analysis":{"summary":"Quase","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"partial","limitations":["Faltou o autor."]}"#)
    #expect(limited.galleryStatusLine == "Faltou o autor.")

    let echoed = try reference(#""id":"u","kind":"link","title":"","text":"https://cursor.com/","url":"https://cursor.com","status":"ready","revision":1,\#(created),"analysis":{"summary":"https://cursor.com/","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]},\#(picture)"#)
    #expect(echoed.isIncomplete)
    #expect(echoed.galleryStatusLine == "A foto ou o clipe não chegou.")

    let blank = try reference(#""id":"b","kind":"link","title":"","text":"","url":"https://www.youtube.com/watch?v=abc","status":"ready","revision":1,\#(created)"#)
    #expect(!blank.isWebsite)
    #expect(!blank.isSocialPost)
    #expect(blank.isIncomplete)

    let narrated = try reference(#""id":"y","kind":"link","title":"Talk","text":"","url":"https://www.youtube.com/watch?v=abc","status":"ready","revision":1,\#(created),"analysis":{"summary":"Uma palestra","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"full","limitations":[]}"#)
    #expect(!narrated.isIncomplete)
}

@Test func errorRetriesWithoutTheFlagAndArchivedItemsDoNot() throws {
    let failed = try reference(#""id":"e","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"error","revision":2,\#(created)"#)
    #expect(failed.mediaIncomplete == nil)
    #expect(!failed.isIncomplete)
    #expect(failed.showsAnalysisRetry)
    #expect(failed.galleryStatusLine == "Falha na análise")

    let archived = try reference(#""id":"a","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"error","revision":2,\#(created),"archived_at":"2026-09-20T16:00:00Z","media_incomplete":true"#)
    #expect(!archived.isIncomplete)
    #expect(!archived.showsAnalysisRetry)
    #expect(archived.galleryStatusLine == nil)
}

@Test func queuedAndProcessingStatusLinesAndStuckRetry() throws {
    let queued = try reference(#""id":"q","kind":"link","title":"Post","text":"","url":"https://x.com/ada/status/1","status":"queued","revision":1,\#(created)"#)
    #expect(queued.galleryStatusLine == "Na fila para análise")
    #expect(!queued.showsAnalysisRetry(at: queued.updatedAt.addingTimeInterval(179)))
    #expect(queued.analysisIsStuck(at: queued.updatedAt.addingTimeInterval(180)))
    #expect(queued.showsAnalysisRetry(at: queued.updatedAt.addingTimeInterval(180)))

    let processing = try reference(#""id":"p","kind":"note","title":"Nota","text":"Oi","url":null,"status":"processing","revision":1,\#(created)"#)
    #expect(processing.galleryStatusLine == "Analisando")
    #expect(processing.showsAnalysisRetry(at: processing.updatedAt.addingTimeInterval(180)))

    let archived = try reference(#""id":"a","kind":"note","title":"Nota","text":"Oi","url":null,"status":"queued","revision":1,\#(created),"archived_at":"2026-09-20T16:00:00Z""#)
    #expect(!archived.analysisIsStuck(at: archived.updatedAt.addingTimeInterval(600)))
    #expect(!archived.showsAnalysisRetry(at: archived.updatedAt.addingTimeInterval(600)))
}

@Test func retryBodySendsFetchScopeAndCanOmitIt() throws {
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnalysisRetryBody(revision: 4))) as! [String: Any]
    #expect(sent["revision"] as? Int == 4)
    #expect(sent["scope"] as? String == "fetch")

    let omitted = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnalysisRetryBody(revision: 4, scope: nil))
    ) as! [String: Any]
    #expect(omitted["revision"] as? Int == 4)
    #expect(omitted["scope"] == nil)
}

@Test func retryConflictAndRateLimitUseFriendlyCopy() {
    #expect(AnalysisRetry.failureCopy(QueepError.conflict) == "Essa referência mudou. Atualize a biblioteca e tente analisar de novo.")
    #expect(AnalysisRetry.failureCopy(QueepError.rateLimited(retryAfter: nil)) == "Muitas tentativas. Espere um pouco e tente de novo.")
    #expect(AnalysisRetry.failureCopy(QueepError.rateLimited(retryAfter: 12)) == "Muitas tentativas. Tente de novo em 12 segundos.")
    #expect(AnalysisRetry.limitCopy(retryAfter: 1) == "Muitas tentativas. Tente de novo em 1 segundo.")
    #expect(AnalysisRetry.limitCopy(retryAfter: 90) == "Muitas tentativas. Tente de novo em 2 minutos.")
    #expect(AnalysisRetry.failureCopy(QueepError.unavailable) == QueepError.unavailable.localizedDescription)
}

@Test func retryAfterHeaderParsesSecondsAndHTTPDate() throws {
    let url = try #require(URL(string: "https://queep.test/retry"))
    let seconds = try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "15"]))
    #expect(APIClient.retryAfterSeconds(seconds) == 15)

    let missing = try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: [:]))
    #expect(APIClient.retryAfterSeconds(missing) == nil)

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let dated = try #require(HTTPURLResponse(
        url: url, statusCode: 429, httpVersion: nil,
        headerFields: ["Retry-After": "Tue, 14 Nov 2023 22:13:40 GMT"]
    ))
    #expect(APIClient.retryAfterSeconds(dated, now: now) == 20)
}
