import Foundation
import QueepCore
import UniformTypeIdentifiers

struct IncomingReference: Sendable {
    let id = UUID()
    var title = ""
    let text: String
    let url: String?
    let image: Data?
    var media: ImportedMedia? = nil

    static func text(_ raw: String) throws -> Self {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = Capture(kind: "link", title: "", text: "", url: text)
        if !text.contains(where: \.isWhitespace), link.isValid {
            return Self(text: "", url: text, image: nil)
        }
        guard Capture(kind: "note", title: "", text: text).isValid else {
            throw QueepError.server("Envie uma nota de até 30 mil caracteres ou um link HTTP válido.")
        }
        return Self(text: text, url: nil, image: nil)
    }

    func save(using client: APIClient) async throws -> Reference {
        if let media { return try await client.uploadMedia(id: id, title: title, file: media.file.url) }
        if let image { return try await client.uploadImage(id: id, title: title, data: image) }
        return try await client.create(id: id, capture: Capture(
            kind: url == nil ? "note" : "link", title: title, text: text, url: url))
    }
}

@MainActor
enum IncomingLoader {
    static func load(_ providers: [NSItemProvider], context: String = "") async throws -> IncomingReference {
        guard providers.count <= 10 else { throw QueepError.server("Compartilhe uma referência por vez.") }
        var links: [String] = []
        var files: [URL] = []
        var texts = context.isEmpty ? [] : [context]
        var images: [NSItemProvider] = []
        var media: [NSItemProvider] = []
        for provider in providers {
            if isMedia(provider) {
                media.append(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let url = try await loadURL(provider)
                if url.isFileURL {
                    files.append(url)
                } else if Capture(kind: "link", title: "", text: "", url: url.absoluteString).isValid,
                          !links.contains(url.absoluteString) {
                    links.append(url.absoluteString)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                images.append(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                texts.append(try await loadText(provider))
            }
        }
        // Instagram/Twitter attach the post URL, a thumbnail and extra proprietary types.
        // Prefer the actual movie/audio file; keep URL over a preview image.
        if let provider = media.first {
            return IncomingReference(text: "", url: nil, image: nil, media: try await loadMedia(provider))
        }
        if let file = files.first(where: isMediaFile) {
            return IncomingReference(text: "", url: nil, image: nil,
                media: try await ImportedMedia.prepare(url: file))
        }
        if let link = links.first {
            let text = texts.filter { $0 != link }.joined(separator: "\n")
            return IncomingReference(text: text, url: link, image: nil)
        }
        if let file = files.first {
            let image = try await Task.detached { try ImportedImage.prepare(url: file, maxPixels: 2048) }.value
            return IncomingReference(text: "", url: nil, image: image.data)
        }
        if let provider = images.first {
            let image = try await loadImage(provider)
            return IncomingReference(text: "", url: nil, image: image.data)
        }
        let note = texts.joined(separator: "\n")
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QueepError.server("Compartilhe um link, texto, imagem, áudio ou vídeo.")
        }
        return try IncomingReference.text(note)
    }

    private static func isMedia(_ provider: NSItemProvider) -> Bool {
        mediaTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }

    private static let mediaTypes: [UTType] = [
        .movie, .mpeg4Movie, .quickTimeMovie, .video, .audio, .mpeg4Audio
    ]

    private static func isMediaFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio) || type.conforms(to: .video)
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = value as? URL { continuation.resume(returning: url) }
                else if let text = value as? String, let url = URL(string: text) { continuation.resume(returning: url) }
                else if let data = value as? Data, let text = String(data: data, encoding: .utf8),
                        let url = URL(string: text) { continuation.resume(returning: url) }
                else { continuation.resume(throwing: QueepError.invalidCapture) }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = value as? String { continuation.resume(returning: text) }
                else if let data = value as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                }
                else { continuation.resume(throwing: QueepError.invalidCapture) }
            }
        }
    }

    private static func loadImage(_ provider: NSItemProvider) async throws -> ImportedImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw QueepError.invalidCapture }
                    // Provider URLs are temporary: read and normalize before this callback returns.
                    continuation.resume(returning: try ImportedImage.prepare(url: url, maxPixels: 2048))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func loadMedia(_ provider: NSItemProvider) async throws -> ImportedMedia {
        let type = mediaTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) } ?? .movie
        let copy: TemporaryMediaFile = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw QueepError.invalidCapture }
                    continuation.resume(returning: try ImportedMedia.copy(url: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
        return try await ImportedMedia.prepare(copy: copy)
    }
}
