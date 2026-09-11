import CoreTransferable
import Foundation
import ImageIO
import QueepCore
import UniformTypeIdentifiers

struct ImportedImage: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try prepare(url: received.file)
        }
    }

    static func prepare(url: URL) throws -> ImportedImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 32 * 1024 * 1024 else {
            throw QueepError.server("Escolha uma imagem de até 32 MB.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier,
               UTType.heif.identifier].contains(type),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw QueepError.server("Escolha uma imagem estática JPEG, PNG ou HEIC.")
        }
        let alpha = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
        let destinationType = alpha ? UTType.png : UTType.jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, destinationType.identifier as CFString, 1, nil) else {
            throw QueepError.server("Não foi possível preparar a imagem.")
        }
        // Orientation is applied above; the new image carries no source EXIF/GPS metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 12 * 1024 * 1024 else {
            throw QueepError.server("A imagem é muito grande. Reduza a resolução e tente novamente.")
        }
        return ImportedImage(data: data as Data)
    }
}
