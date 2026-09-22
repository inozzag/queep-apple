import XCTest

@MainActor
final class SpacesTests: XCTestCase {
    func testCreateAssignAndFilterSpaceOnMac() async throws {
        try await runSpacesJourney()
    }
}
