@preconcurrency import AVFoundation
import CoreTransferable
import Foundation
import QueepCore
import UniformTypeIdentifiers

final class TemporaryMediaFile: @unchecked Sendable {
    private static let startupCleanup: Void = removeAbandonedFiles()
    let url: URL
    init(extension suffix: String) {
        Self.cleanOnce()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("queep-media-\(UUID().uuidString).\(suffix)")
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    static func cleanOnce() { _ = startupCleanup }

    /// Only our regular, UUID-named files; recent files may belong to an ongoing import.
    static func removeAbandonedFiles(in directory: URL = FileManager.default.temporaryDirectory,
                                     now: Date = Date()) {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let files = try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
        for file in files {
            let stem = file.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix("queep-media-"), UUID(uuidString: String(stem.dropFirst(12))) != nil,
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > 24 * 60 * 60 else { continue }
            try? manager.removeItem(at: file)
        }
    }
}

struct ImportedMedia: Transferable, Sendable {
    let file: TemporaryMediaFile
    let kind: String
    let duration: Double

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try await prepare(url: received.file)
        }
        FileRepresentation(importedContentType: .audio) { received in
            try await prepare(url: received.file)
        }
    }

    static func copy(url: URL) throws -> TemporaryMediaFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw QueepError.server("Escolha um arquivo de áudio ou vídeo.") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0,
              size <= 150 * 1024 * 1024 else {
            throw QueepError.server("Escolha um arquivo original de até 150 MB.")
        }
        let copy = TemporaryMediaFile(extension: url.pathExtension.isEmpty ? "media" : url.pathExtension)
        try FileManager.default.copyItem(at: url, to: copy.url)
        return copy
    }

    static func prepare(url: URL) async throws -> ImportedMedia {
        try await prepare(copy: copy(url: url))
    }

    static func prepare(copy: TemporaryMediaFile) async throws -> ImportedMedia {
        let asset = AVURLAsset(url: copy.url)
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0, seconds <= 300 else {
            throw QueepError.server("Escolha um áudio ou vídeo de até 5 minutos.")
        }
        let video = try await !asset.loadTracks(withMediaType: .video).isEmpty
        let audio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        guard video || audio else { throw QueepError.server("Não foi possível ler esta mídia.") }
        let file = TemporaryMediaFile(extension: video ? "mp4" : "m4a")
        guard let exporter = AVAssetExportSession(asset: asset,
            presetName: video ? AVAssetExportPreset1280x720 : AVAssetExportPresetAppleM4A) else {
            throw QueepError.server("Não foi possível preparar este formato.")
        }
        exporter.outputURL = file.url
        exporter.outputFileType = video ? .mp4 : .m4a
        exporter.metadata = []
        exporter.shouldOptimizeForNetworkUse = true
        await withTaskCancellationHandler {
            await exporter.export()
        } onCancel: { exporter.cancelExport() }
        try Task.checkCancellation()
        guard exporter.status == .completed else {
            throw QueepError.server("Não foi possível preparar a mídia. Escolha outro arquivo.")
        }
        let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 25 * 1024 * 1024 else {
            throw QueepError.server("A mídia preparada excede 25 MB. Escolha um trecho menor.")
        }
        return ImportedMedia(file: file, kind: video ? "video" : "audio", duration: seconds)
    }
}
