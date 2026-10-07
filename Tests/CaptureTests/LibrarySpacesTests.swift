import Foundation
import XCTest
import QueepCore

private final class SpacesTransport: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 503
    nonisolated(unsafe) static var response = Data(#"{"detail":"Sem conexão"}"#.utf8)

    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor
final class LibrarySpacesTests: XCTestCase {
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpacesTransport.self]
        return APIClient(baseURL: URL(string: "https://spaces.example.test")!,
                         session: URLSession(configuration: configuration), token: { "test" })
    }

    private func reference() throws -> Reference {
        let raw = #"{"id":"123","kind":"note","title":"Ideia","text":"Texto","status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","space_ids":["one"]}"#
        return try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    }

    func testFailedToggleRollsBackMembershipAndCountInSelectedSpace() async throws {
        SpacesTransport.status = 503
        SpacesTransport.response = Data(#"{"detail":"Sem conexão"}"#.utf8)
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        let space = Space(id: "one", name: "Cliente", sortIndex: 0, referenceCount: 1)
        let ref = try reference()
        store.spaces = [space]
        store.items = [ref]
        store.hasLoaded = true
        store.selectSpace(space.id)
        store.items = [ref]
        store.hasLoaded = true
        await store.assignSpace(space, references: [ref], adding: false, client: client(), account: account)
        XCTAssertEqual(store.items.map(\.id), [ref.id])
        XCTAssertEqual(store.items.first?.membershipIDs, [space.id])
        XCTAssertEqual(store.spaces.first?.referenceCount, 1)
        XCTAssertNotNil(store.spaceError)
        XCTAssertFalse(store.spaceMutating)
    }

    func testDuplicateCreateRollsBackOptimisticSpace() async {
        SpacesTransport.status = 409
        SpacesTransport.response = Data(#"{"detail":"Já existe"}"#.utf8)
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        let original = Space(id: "one", name: "Cliente", sortIndex: 0)
        store.spaces = [original]
        let saved = await store.saveSpace(client(), account: account, name: "CLIENTE")
        XCTAssertFalse(saved)
        XCTAssertEqual(store.spaces, [original])
        XCTAssertEqual(store.spaceError, "Já existe um Space com este nome.")
    }

    func testOfflineCacheRestoresSelectedSpaceAndDoesNotCrossAccounts() async throws {
        SpacesTransport.status = 200
        SpacesTransport.response = Data(#"{"id":"123","kind":"note","title":"Ideia","text":"Texto","status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","space_ids":["one"]}"#.utf8)
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        let space = Space(id: "one", name: "Cliente", sortIndex: 0, referenceCount: 1)
        let ref = try reference()
        store.spaces = [space]
        store.items = [ref]
        store.hasLoaded = true
        store.selectSpace(space.id)
        store.items = [ref]
        store.hasLoaded = true
        await store.assignSpace(space, references: [ref], adding: true, client: client(), account: account)
        let restored = LibraryStore()
        restored.reset(for: account)
        XCTAssertEqual(restored.selectedSpaceID, space.id)
        XCTAssertEqual(restored.items.map(\.id), [ref.id])
        restored.selectSpace(nil)
        XCTAssertEqual(restored.items.map(\.id), [ref.id])
        restored.reset(for: UUID().uuidString)
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertTrue(restored.spaces.isEmpty)
        XCTAssertNil(restored.selectedSpaceID)
        restored.reset(for: nil)
    }

    func testLoadMoreStopsWhenTheCursorDoesNotAdvanceAndAFreshCacheSkipsTheNetwork() async throws {
        SpacesTransport.hits = 0
        SpacesTransport.status = 200
        SpacesTransport.response = page(ids: ["a"], cursor: "c1")
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        await store.refresh(client(), account: account, force: true)
        XCTAssertEqual(store.items.map(\.id), ["a"])
        XCTAssertEqual(store.nextCursor, "c1")
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.loadingMore)
        let afterFirst = SpacesTransport.hits
        XCTAssertGreaterThan(afterFirst, 0)
        await store.refresh(client(), account: account)
        XCTAssertEqual(SpacesTransport.hits, afterFirst)

        SpacesTransport.response = page(ids: ["a"], cursor: "c1")
        await store.refresh(client(), account: account, more: true)
        XCTAssertEqual(store.items.map(\.id), ["a"])
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.loadingMore)
        let afterStuck = SpacesTransport.hits
        await store.refresh(client(), account: account, more: true)
        XCTAssertEqual(SpacesTransport.hits, afterStuck, "A failed or stuck cursor must not request another page")
    }

    func testFailedRefreshKeepsVisibleItemsAndBlocksTheNextPage() async throws {
        SpacesTransport.hits = 0
        SpacesTransport.status = 200
        SpacesTransport.response = page(ids: ["a"], cursor: "c1")
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        await store.refresh(client(), account: account, force: true)
        SpacesTransport.status = 503
        SpacesTransport.response = Data(#"{"detail":"Sem conexão"}"#.utf8)
        await store.refresh(client(), account: account, force: true)
        XCTAssertEqual(store.items.map(\.id), ["a"])
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.refreshing)
        XCTAssertNotNil(store.error)
        let hits = SpacesTransport.hits
        await store.refresh(client(), account: account, more: true)
        XCTAssertEqual(SpacesTransport.hits, hits)
        XCTAssertEqual(store.items.map(\.id), ["a"])
    }

    func testDiskCacheRestoresOnlyTheFirstPage() async throws {
        SpacesTransport.hits = 0
        SpacesTransport.status = 200
        SpacesTransport.response = page(ids: ["a"], cursor: "c1")
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        await store.refresh(client(), account: account, force: true)
        SpacesTransport.response = page(ids: ["b"], cursor: "c2")
        await store.refresh(client(), account: account, more: true)
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        XCTAssertEqual(store.nextCursor, "c2")
        let restored = LibraryStore()
        restored.reset(for: account)
        XCTAssertEqual(restored.items.map(\.id), ["a"])
        XCTAssertEqual(restored.nextCursor, "c1")
        XCTAssertTrue(restored.hasLoaded)
        XCTAssertFalse(restored.loading)
        SpacesTransport.response = page(ids: ["b"], cursor: "c2")
        let beforeNext = SpacesTransport.hits
        await restored.refresh(client(), account: account, more: true)
        XCTAssertGreaterThan(SpacesTransport.hits, beforeNext)
        XCTAssertEqual(restored.items.map(\.id), ["a", "b"])
        XCTAssertEqual(restored.nextCursor, "c2")
        restored.reset(for: nil)
    }

    func testNearEndUsesASmallThresholdPastTheViewport() {
        let viewport = CGRect(x: 0, y: 100, width: 800, height: 700)
        XCTAssertFalse(LibraryEndTrigger.isNearEnd(tailMinY: viewport.maxY + 400, viewport: viewport))
        XCTAssertTrue(LibraryEndTrigger.isNearEnd(tailMinY: viewport.maxY + 40, viewport: viewport))
        XCTAssertTrue(LibraryEndTrigger.isNearEnd(tailMinY: viewport.midY, viewport: viewport))
        XCTAssertFalse(LibraryEndTrigger.isNearEnd(tailMinY: viewport.minY - 400, viewport: viewport))
        XCTAssertFalse(LibraryEndTrigger.isNearEnd(tailMinY: 0, viewport: .null))
    }

    func testScrollDistanceLoadsOnlyNearTheRealEnd() {
        let middle = LibraryEndTrigger.distanceToEnd(contentHeight: 4000, contentOffsetY: 200, containerHeight: 800)
        XCTAssertEqual(middle, 3000)
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: middle, containerHeight: 800))
        let withinScreen = LibraryEndTrigger.distanceToEnd(contentHeight: 4000, contentOffsetY: 2500, containerHeight: 800)
        XCTAssertEqual(withinScreen, 700)
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: withinScreen, containerHeight: 800))
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: 0, containerHeight: 800))
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: -12, containerHeight: 800))
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: 801, containerHeight: 800))
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: .greatestFiniteMagnitude, containerHeight: 800))
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: 0, containerHeight: 0))

        let endOnScreen = LibraryEndTrigger.resolvedDistance(
            contentHeight: 500, contentOffsetY: 0, containerHeight: 800, visibleMaxY: 500, visibleHeight: 500)
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: endOnScreen, containerHeight: 800))

        let staleOffset = LibraryEndTrigger.resolvedDistance(
            contentHeight: 4000, contentOffsetY: 0, containerHeight: 800, visibleMaxY: 3300, visibleHeight: 800)
        XCTAssertEqual(staleOffset, 700)
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: staleOffset, containerHeight: 800))

        let staleVisible = LibraryEndTrigger.resolvedDistance(
            contentHeight: 4000, contentOffsetY: 2500, containerHeight: 800, visibleMaxY: 800, visibleHeight: 800)
        XCTAssertEqual(staleVisible, 700)
        XCTAssertTrue(LibraryEndTrigger.shouldPage(distanceToEnd: staleVisible, containerHeight: 800))

        let middleOfList = LibraryEndTrigger.resolvedDistance(
            contentHeight: 4000, contentOffsetY: 200, containerHeight: 800, visibleMaxY: 1000, visibleHeight: 800)
        XCTAssertGreaterThan(middleOfList, 800)
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: middleOfList, containerHeight: 800))

        let fullContentFrame = LibraryEndTrigger.resolvedDistance(
            contentHeight: 4000, contentOffsetY: 200, containerHeight: 800, visibleMaxY: 4000, visibleHeight: 4000)
        XCTAssertGreaterThan(fullContentFrame, 800)
        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd: fullContentFrame, containerHeight: 800))

        XCTAssertFalse(LibraryEndTrigger.shouldPage(distanceToEnd:
            LibraryEndTrigger.resolvedDistance(contentHeight: 0, contentOffsetY: 0, containerHeight: 0,
                                               visibleMaxY: 0, visibleHeight: 0),
            containerHeight: 0))

        XCTAssertTrue(LibraryEndTrigger.shouldRequestNextPage(
            distanceToEnd: 700, containerHeight: 800, hasCursor: true, inFlight: false))
        XCTAssertFalse(LibraryEndTrigger.shouldRequestNextPage(
            distanceToEnd: 3000, containerHeight: 800, hasCursor: true, inFlight: false))
        XCTAssertFalse(LibraryEndTrigger.shouldRequestNextPage(
            distanceToEnd: 0, containerHeight: 800, hasCursor: false, inFlight: false))
        XCTAssertFalse(LibraryEndTrigger.shouldRequestNextPage(
            distanceToEnd: 0, containerHeight: 800, hasCursor: true, inFlight: true))

        XCTAssertEqual(LibraryEndTrigger.nextShownCount(shown: 18, previousCount: 18, newCount: 36), 36)
        XCTAssertEqual(LibraryEndTrigger.nextShownCount(shown: 18, previousCount: 36, newCount: 54), 18)
        XCTAssertEqual(LibraryEndTrigger.nextShownCount(shown: 18, previousCount: 18, newCount: 10), 10)
    }

    func testLastPageAppendsItemsAndARefreshInFlightDoesNotBlockTheNextPage() async throws {
        SpacesTransport.hits = 0
        SpacesTransport.status = 200
        SpacesTransport.response = page(ids: ["a"], cursor: "c1")
        let account = UUID().uuidString
        let store = LibraryStore()
        store.reset(for: account)
        defer { store.reset(for: nil) }
        await store.refresh(client(), account: account, force: true)
        store.refreshing = true
        store.loading = true
        SpacesTransport.response = page(ids: ["b"], cursor: nil)
        let before = SpacesTransport.hits
        await store.refresh(client(), account: account, more: true)
        XCTAssertGreaterThan(SpacesTransport.hits, before)
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.loadingMore)
        let stuck = SpacesTransport.hits
        await store.refresh(client(), account: account, more: true)
        XCTAssertEqual(SpacesTransport.hits, stuck)
    }

    private func page(ids: [String], cursor: String?) -> Data {
        let items = ids.map { id in
            #"{"id":"\#(id)","kind":"note","title":"\#(id)","text":"T","status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z"}"#
        }.joined(separator: ",")
        if let cursor {
            return Data(#"{"items":[\#(items)],"next_cursor":"\#(cursor)"}"#.utf8)
        }
        return Data(#"{"items":[\#(items)]}"#.utf8)
    }
}
