import AVFoundation
import XCTest
import UniformTypeIdentifiers

@MainActor
final class MediaImportTests: XCTestCase {
    func testAudioAndVideoBecomePlayablePrivateFiles() async throws {
        for (name, suffix, kind) in [("sample-audio", "wav", "audio"), ("sample-video", "mp4", "video")] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
            var media: ImportedMedia? = try await ImportedMedia.prepare(url: url)
            XCTAssertEqual(media?.kind, kind)
            XCTAssertGreaterThan(media?.duration ?? 0, 1)
            let prepared = try XCTUnwrap(media?.file.url)
            XCTAssertNotEqual(prepared, url)
            let playable = try await AVURLAsset(url: prepared).load(.isPlayable)
            XCTAssertTrue(playable)
            media = nil
            XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.path))
        }
    }

    func testSharedVideoSurvivesProviderTemporaryFileRemoval() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-video", withExtension: "mp4"))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.copyItem(at: source, to: temporary)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.movie.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(temporary, false, nil)
            try? FileManager.default.removeItem(at: temporary)
            return nil
        }
        let incoming = try await IncomingLoader.load([provider])
        XCTAssertEqual(incoming.media?.kind, "video")
        XCTAssertNil(incoming.image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(incoming.media?.file.url.path)))
    }
}
