import Foundation
import Testing
@testable import QueepCore

@Test func legacyReferencesDefaultToInboxAndSpaceMembershipSurvivesLocalCache() throws {
    let raw = #"{"id":"123","kind":"note","title":"Ideia","text":"Texto","status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z"}"#
    var reference = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(reference.membershipIDs.isEmpty)
    reference.spaceIds = ["client", "personal"]
    let cached = try JSONDecoder().decode(Reference.self, from: JSONEncoder().encode(reference))
    #expect(cached.membershipIDs == ["client", "personal"])
}

@Test func decodesSpaceCountAndOrder() throws {
    let raw = #"{"id":"client","name":"🎨 Cliente","sort_index":2,"reference_count":12,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z"}"#
    let space = try APIClient.decoder().decode(Space.self, from: Data(raw.utf8))
    #expect(space.sortIndex == 2)
    #expect(space.countLabel == "12 referências")
    #expect(space.name == "🎨 Cliente")
}
