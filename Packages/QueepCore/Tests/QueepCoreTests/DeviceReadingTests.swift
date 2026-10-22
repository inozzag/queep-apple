import Testing
import Foundation
@testable import QueepCore

@Test func readingEncodesTheAPIFieldNamesWithinLimits() throws {
    let reading = DeviceReading(screenText: String(repeating: "a", count: 9000), transcript: "Olá",
                                segments: [.init(start: 400, text: "Olá")],
                                colors: Array(repeating: "#FFFFFF", count: 10), engine: "apple-speech")
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reading.bounded)) as? [String: Any])
    #expect((object["screen_text"] as? String)?.count == 8000)
    #expect((object["colors"] as? [String])?.count == 8)
    let segment = try #require((object["segments"] as? [[String: Any]])?.first)
    #expect(segment["start"] as? Double == 301)
    #expect(object["screenText"] == nil)
}

@Test func emptyReadingIsNotSent() {
    #expect(DeviceReading(engine: "apple-vision").isEmpty)
    #expect(!DeviceReading(colors: ["#000000"]).isEmpty)
}

private struct KeepSecond: SearchChecker {
    func kept(query: String, candidates: [Reference]) async throws -> [String] { [candidates[1].id] }
}

private struct Broken: SearchChecker {
    func kept(query: String, candidates: [Reference]) async throws -> [String] { throw CancellationError() }
}

@Test func checkerFiltersOnlyTheHeadAndFailsOpen() async throws {
    let items = try (0..<8).map { try note("item-\($0)") }
    let filtered = await KeepSecond().filter(query: "hero", items: items)
    #expect(filtered.map(\.id) == ["item-1", "item-6", "item-7"])
    let unchanged = await Broken().filter(query: "hero", items: items)
    #expect(unchanged.map(\.id) == items.map(\.id))
}

private func note(_ id: String) throws -> Reference {
    let raw = """
    {"id":"\(id)","kind":"note","title":"\(id)","text":"","url":null,"status":"ready","revision":1,"created_at":"2026-10-22T15:00:00Z","updated_at":"2026-10-22T16:00:00Z"}
    """
    return try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
}
