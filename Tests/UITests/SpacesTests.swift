import XCTest

@MainActor
final class SpacesTests: XCTestCase {
    func testCreateAssignAndFilterSpaceOnIPhone() async throws {
        try await runSpacesJourney()
    }
}
