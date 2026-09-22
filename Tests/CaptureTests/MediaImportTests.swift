import AVFoundation
import XCTest
import UniformTypeIdentifiers

@MainActor
final class MediaImportTests: XCTestCase {
    func testCrashCleanupOnlyRemovesOldOwnedFiles() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let old = root.appendingPathComponent("queep-media-\(UUID()).mp4")
        let recent = root.appendingPathComponent("queep-media-\(UUID()).m4a")
        let unrelated = root.appendingPathComponent("someone-else.mp4")
        let symlink = root.appendingPathComponent("queep-media-\(UUID()).mp4")
        for file in [old, recent, unrelated] { try Data([1, 2, 3]).write(to: file) }
        let yesterday = Date().addingTimeInterval(-48 * 60 * 60)
        for file in [old, unrelated] {
            try manager.setAttributes([.modificationDate: yesterday], ofItemAtPath: file.path)
        }
        try manager.createSymbolicLink(at: symlink, withDestinationURL: unrelated)
        TemporaryMediaFile.removeAbandonedFiles(in: root)
        XCTAssertFalse(manager.fileExists(atPath: old.path))
        for file in [recent, unrelated, symlink] { XCTAssertTrue(manager.fileExists(atPath: file.path)) }
    }

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
        let incoming = try await IncomingLoader.load([provider], authorizeMedia: {})
        XCTAssertEqual(incoming.media?.kind, "video")
        XCTAssertNil(incoming.image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(incoming.media?.file.url.path)))
    }
}
