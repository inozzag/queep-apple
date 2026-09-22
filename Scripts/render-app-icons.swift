import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

func render(svg: URL, size: Int, dest: URL, opaqueBackground: NSColor? = nil) throws {
    guard let image = NSImage(contentsOf: svg) else {
        throw NSError(domain: "render-app-icons", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not load \(svg.lastPathComponent)"])
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "render-app-icons", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap"])
    }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "render-app-icons", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create graphics context"])
    }
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    if let opaqueBackground {
        opaqueBackground.setFill()
        rect.fill()
    } else {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-app-icons", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: dest)
}

let appSVG = root.appendingPathComponent("Sources/Shared/Assets.xcassets/AppIcon.appiconset/AppIcon.svg")
let appDir = root.appendingPathComponent("Sources/Shared/Assets.xcassets/AppIcon.appiconset")
let cream = NSColor(srgbRed: 252 / 255, green: 252 / 255, blue: 252 / 255, alpha: 1)
try render(svg: appSVG, size: 1024, dest: appDir.appendingPathComponent("AppIcon.png"), opaqueBackground: cream)
for side in [16, 32, 64, 128, 256, 512] {
    try render(svg: appSVG, size: side,
               dest: appDir.appendingPathComponent("AppIcon-mac-\(side).png"),
               opaqueBackground: cream)
}

let shareSVG = root.appendingPathComponent("Sources/Share/Assets.xcassets/AppIcon.appiconset/AppIcon.svg")
let sharePNG = root.appendingPathComponent("Sources/Share/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try render(svg: shareSVG, size: 1024, dest: sharePNG)
print("Rendered app and share icons")
