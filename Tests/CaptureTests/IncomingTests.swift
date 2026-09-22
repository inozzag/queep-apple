import XCTest
import UniformTypeIdentifiers
import ImageIO
import AppKit
import QueepCore

@MainActor
final class IncomingTests: XCTestCase {
    func testTextDistinguishesLinksAndNotes() throws {
        let link = try IncomingReference.text("  https://example.com/reference?q=swift\n")
        XCTAssertEqual(link.url, "https://example.com/reference?q=swift")
        XCTAssertTrue(link.text.isEmpty)
        let note = try IncomingReference.text("Veja https://example.com para estudar Swift")
        XCTAssertNil(note.url)
        XCTAssertTrue(note.text.hasPrefix("Veja"))
        XCTAssertThrowsError(try IncomingReference.text(" \n"))
        XCTAssertThrowsError(try IncomingReference.text(String(repeating: "a", count: 30_001)))
    }

    func testURLWinsOverItsPreviewImage() async throws {
        let incoming = try await IncomingLoader.load([
            NSItemProvider(object: URL(string: "https://example.com/reference")! as NSURL),
            NSItemProvider(object: NSImage(size: .init(width: 10, height: 10)))
        ], context: "Referência de interface")
        XCTAssertEqual(incoming.url, "https://example.com/reference")
        XCTAssertEqual(incoming.text, "Referência de interface")
        XCTAssertNil(incoming.image)
    }

    func testIgnoresUnknownAttachmentsAndKeepsTheLink() async throws {
        let incoming = try await IncomingLoader.load([
            NSItemProvider(object: URL(string: "https://instagram.com/reel/demo")! as NSURL),
            NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.pdf.identifier)
        ])
        XCTAssertEqual(incoming.url, "https://instagram.com/reel/demo")
        XCTAssertNil(incoming.media)
    }

    func testVideoWinsOverPostURL() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-video", withExtension: "mp4"))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.copyItem(at: source, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let video = NSItemProvider()
        video.registerFileRepresentation(forTypeIdentifier: UTType.movie.identifier,
                                         fileOptions: [], visibility: .all) { completion in
            completion(temporary, false, nil)
            return nil
        }
        let incoming = try await IncomingLoader.load([
            NSItemProvider(object: URL(string: "https://x.com/user/status/1")! as NSURL),
            video
        ], authorizeMedia: {})
        XCTAssertEqual(incoming.media?.kind, "video")
        XCTAssertNil(incoming.url)
    }

    func testDeniedMediaDoesNotLoadOrPrepareProvider() async throws {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.movie.identifier,
                                            fileOptions: [], visibility: .all) { _ in
            XCTFail("A blocked movie must never be loaded")
            return nil
        }
        do {
            _ = try await IncomingLoader.load([provider], authorizeMedia: {
                throw QueepError.planRequired(.media(for: .pro))
            })
            XCTFail("Pro cannot import a movie")
        } catch QueepError.planRequired(let requirement) {
            XCTAssertEqual(requirement.requiredPlan, .max)
        }
    }

    func testTextProviderAndEmptyShare() async throws {
        let incoming = try await IncomingLoader.load([NSItemProvider(object: "Nota compartilhada" as NSString)])
        XCTAssertEqual(incoming.text, "Nota compartilhada")
        do { _ = try await IncomingLoader.load([]); XCTFail("Empty shares must not be saved") }
        catch { }
    }

    func testUnsupportedSharesAreRejected() async throws {
        let invalid: [[NSItemProvider]] = [
            [NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.pdf.identifier)],
            [NSItemProvider(object: URL(string: "ftp://example.com/a")! as NSURL)]
        ]
        for providers in invalid {
            do { _ = try await IncomingLoader.load(providers); XCTFail("Unsupported share accepted") }
            catch { }
        }
    }

    func testTemporaryImageIsReadAndOptimizedBeforeProviderReturns() async throws {
        let context = CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(.init(x: 0, y: 0, width: 2400, height: 1200))
        let data = try ImportedImage.encode(context.makeImage()!).data
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(file, false, nil)
            return nil
        }
        let incoming = try await IncomingLoader.load([provider])
        let bytes = try XCTUnwrap(incoming.image)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2048)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 1024)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertThrowsError(try ImportedImage.prepare(data: Data("not an image".utf8)))
    }
}
