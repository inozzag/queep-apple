import Foundation
import XCTest
import QueepCore

private final class SpacesTransport: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 503
    nonisolated(unsafe) static var response = Data(#"{"detail":"Sem conexão"}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
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
}
