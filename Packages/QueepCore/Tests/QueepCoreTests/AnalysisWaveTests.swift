import Testing
@testable import QueepCore

@Test func pollStopsOnReadyAndError() {
    let policy = AnalysisPoll.Policy.detail
    let failed = AnalysisPoll.afterFetch(status: "error", galleryEmpty: true, snapshot: .init(), policy: policy)
    #expect(failed.1 == .stop)
    let ready = AnalysisPoll.afterFetch(status: "ready", galleryEmpty: true, snapshot: .init(), policy: policy)
    #expect(ready.1 == .stop)
    let working = AnalysisPoll.afterFetch(status: "processing", galleryEmpty: true, snapshot: .init(), policy: policy)
    #expect(working.1 == .keepPolling)
}

@Test func pollWaitsForPostPhotosThenStops() {
    let policy = AnalysisPoll.Policy.post
    var snapshot = AnalysisPoll.Snapshot()
    var outcome = AnalysisPoll.Outcome.keepPolling
    for _ in 0..<14 {
        (snapshot, outcome) = AnalysisPoll.afterFetch(status: "ready", galleryEmpty: true, snapshot: snapshot, policy: policy)
        #expect(outcome == .keepPolling)
    }
    (_, outcome) = AnalysisPoll.afterFetch(status: "ready", galleryEmpty: true, snapshot: snapshot, policy: policy)
    #expect(outcome == .stop)

    let filled = AnalysisPoll.afterFetch(status: "ready", galleryEmpty: false, snapshot: .init(), policy: policy)
    #expect(filled.1 == .stop)
}

@Test func pollKeepsGoingAfterANetworkErrorUntilTheCap() {
    let policy = AnalysisPoll.Policy.analysis
    var snapshot = AnalysisPoll.Snapshot()
    var outcome = AnalysisPoll.Outcome.keepPolling
    (snapshot, outcome) = AnalysisPoll.afterNetworkError("Não foi possível conectar. Tente novamente.", snapshot: snapshot, policy: policy)
    #expect(outcome == .keepPolling)
    (snapshot, outcome) = AnalysisPoll.afterNetworkError("Não foi possível conectar. Tente novamente.", snapshot: snapshot, policy: policy)
    #expect(outcome == .keepPolling)
    (snapshot, outcome) = AnalysisPoll.afterNetworkError("offline", snapshot: snapshot, policy: policy)
    #expect(outcome == .failed("offline"))

    let recovered = AnalysisPoll.afterFetch(status: "processing", galleryEmpty: true, snapshot: snapshot, policy: policy)
    #expect(recovered.0.consecutiveNetworkFailures == 0)
    #expect(recovered.1 == .keepPolling)
}

@Test func pollStopsWhenTheAttemptCapIsReached() {
    let policy = AnalysisPoll.Policy(maxAttempts: 2, maxNetworkFailures: 5, waitsForGallery: false, readyGalleryPolls: 1)
    var snapshot = AnalysisPoll.Snapshot()
    var outcome = AnalysisPoll.Outcome.stop
    (snapshot, outcome) = AnalysisPoll.afterFetch(status: "queued", galleryEmpty: true, snapshot: snapshot, policy: policy)
    #expect(outcome == .keepPolling)
    (_, outcome) = AnalysisPoll.afterFetch(status: "queued", galleryEmpty: true, snapshot: snapshot, policy: policy)
    #expect(outcome == .stop)
}

@Test func pollResumesWhenRetryReturnsQueuedOrProcessing() {
    #expect(AnalysisPoll.resumes(afterRetry: "queued"))
    #expect(AnalysisPoll.resumes(afterRetry: "processing"))
    #expect(!AnalysisPoll.resumes(afterRetry: "error"))
    #expect(!AnalysisPoll.resumes(afterRetry: "ready"))
}
