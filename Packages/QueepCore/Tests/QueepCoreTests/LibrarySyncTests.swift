import Testing
@testable import QueepCore

@Test func refreshContinuesWhileAnalysisIsOpenWithoutAnItemCap() {
    let manyReady = Array(repeating: "ready", count: 50)
    #expect(!LibrarySync.shouldRefresh(statuses: manyReady, detailOpen: false))
    #expect(LibrarySync.shouldRefresh(statuses: manyReady + ["processing"], detailOpen: false))
    #expect(LibrarySync.shouldRefresh(statuses: manyReady, detailOpen: true))
    #expect(LibrarySync.shouldRefresh(statuses: ["queued"], detailOpen: false))
    #expect(LibrarySync.analyzingTile("queued") == "Aguardando análise…")
    #expect(LibrarySync.analyzingTile("processing") == "Analisando…")
    #expect(LibrarySync.analyzingTile("ready") == nil)
}
