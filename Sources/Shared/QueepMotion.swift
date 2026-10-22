import SwiftUI

/// The Queep motion from Figma (`Queep V2`, frame `11:38167`): the mark wakes up, shapes orbit in
/// and fall into a portal. It loops every 11.8s. The keys are baked and linear, exported from Figma
/// into `Motion/QueepMotion.json`, and drawn on a Canvas so the mark stays sharp at any size.
struct QueepMotionView: View {
    /// Shapes and petals.
    var ink: Color = Theme.ink
    /// Eyes, the portal arms and the ball. The page colour behind the motion.
    var paper: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion || QueepMotionRig.shared == nil {
                GeometryReader { geo in
                    QueepMark(size: geo.size.width * 365.163 / 1080, color: ink)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    Canvas { context, size in
                        QueepMotionRig.shared?.draw(in: context, size: size, time: elapsed, ink: ink, paper: paper)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// White page with the motion small in the middle: the app's loading screen.
struct QueepLoadingScreen: View {
    var label = "Abrindo sua biblioteca…"

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            QueepMotionView()
                .frame(width: 168, height: 168)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("entry.loading")
    }
}

/// Decoded rig. Immutable after load, so it is shared across views.
final class QueepMotionRig: @unchecked Sendable {
    static let shared: QueepMotionRig? = QueepMotionRig()

    private struct File: Decodable {
        let duration: Double
        let nodes: [String: [String: [[Double]]]]
        let paths: [String: String]
    }

    /// Layout of each layer in its parent, from the Figma frame (x, y, width, height).
    private static let frames: [String: CGRect] = [
        "camera": CGRect(x: 0, y: 0, width: 1080, height: 1080),
        "queep": CGRect(x: 357.42, y: 362.64, width: 365.163, height: 354.73),
        "petalsB": CGRect(x: 12.68, y: 13, width: 328.465, height: 333.029),
        "face": CGRect(x: 105.06, y: 165.55, width: 105.06, height: 94.358),
        "eyeL": CGRect(x: 0, y: 0, width: 36.771, height: 89.105),
        "eyeR": CGRect(x: 68.29, y: 5.25, width: 36.771, height: 89.105),
        "lidL": CGRect(x: -18.98, y: -67.29, width: 74.736, height: 62.573),
        "lidR": CGRect(x: 49.31, y: -62.03, width: 74.736, height: 62.573),
        "vortex": CGRect(x: 80, y: 70, width: 210, height: 220),
        "armInner": CGRect(x: 0, y: 0, width: 210, height: 220),
        "armOuter": CGRect(x: 0, y: 0, width: 210, height: 220),
        "ball": CGRect(x: 166.61, y: 161.61, width: 36.771, height: 36.771),
        "shape1": CGRect(x: 772, y: 152, width: 140, height: 140),
        "shape2": CGRect(x: 128, y: 418, width: 100, height: 100),
        "shape3": CGRect(x: 806, y: 760, width: 104, height: 104),
        "shape4": CGRect(x: 162, y: 136, width: 120, height: 120),
        "shape5": CGRect(x: 890, y: 480, width: 80, height: 80),
        "shape6": CGRect(x: 490, y: 894, width: 116, height: 116),
        "shape7": CGRect(x: 155, y: 785, width: 90, height: 90),
        "shape8": CGRect(x: 499, y: 59, width: 98, height: 98),
    ]

    private let duration: Double
    private let tracks: [String: [String: [[Double]]]]
    private let paths: [String: Path]

    private init?() {
        guard let url = Bundle.main.url(forResource: "QueepMotion", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.duration > 0 else { return nil }
        duration = file.duration
        tracks = file.nodes
        paths = file.paths.mapValues(SVGPath.parse)
    }

    func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, paper: Color) {
        let t = time.truncatingRemainder(dividingBy: duration) / duration
        var root = context
        let unit = min(size.width, size.height) / 1080
        root.translateBy(x: (size.width - 1080 * unit) / 2, y: (size.height - 1080 * unit) / 2)
        root.scaleBy(x: unit, y: unit)
        let inkShading = GraphicsContext.Shading.color(ink)
        let paperShading = GraphicsContext.Shading.color(paper)
        let arm = StrokeStyle(lineWidth: 8, lineJoin: .miter, miterLimit: 4)
        let seam = StrokeStyle(lineWidth: 8, lineJoin: .round)

        layer("camera", in: root, t: t, unit: unit) { camera, _ in
            layer("queep", in: camera, t: t, unit: unit) { queep, _ in
                layer("petalsB", in: queep, t: t, unit: unit) { context, _ in
                    fill("petalsB", in: context, with: inkShading)
                }
                fill("petalsA", in: queep, with: inkShading)
                layer("face", in: queep, t: t, unit: unit) { face, _ in
                    for eye in ["eyeL", "eyeR"] {
                        layer(eye, in: face, t: t, unit: unit) { context, size in
                            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18.385),
                                         with: paperShading)
                        }
                    }
                    for (lid, degrees) in [("lidL", 24.0), ("lidR", -24.0)] {
                        layer(lid, in: face, t: t, unit: unit) { context, size in
                            var context = context
                            context.translateBy(x: size.width / 2, y: size.height / 2)
                            context.rotate(by: .degrees(degrees))
                            context.fill(Path(CGRect(x: -32, y: -20, width: 64, height: 40)), with: inkShading)
                        }
                    }
                }
                layer("vortex", in: queep, t: t, unit: unit) { vortex, _ in
                    layer("armInner", in: vortex, t: t, unit: unit) { context, _ in
                        guard let path = paths["armInner"] else { return }
                        var context = context
                        context.translateBy(x: -3.99, y: 0)
                        context.fill(path, with: paperShading)
                        context.stroke(path, with: paperShading, style: arm)
                    }
                    layer("armOuter", in: vortex, t: t, unit: unit) { context, _ in
                        guard let path = paths["armOuter"] else { return }
                        var context = context
                        context.translateBy(x: 0, y: -4)
                        if let mask = paths["armSeamMask"] {
                            var seamed = context
                            seamed.clip(to: mask)
                            seamed.fill(path, with: paperShading)
                            seamed.stroke(path, with: paperShading, style: seam)
                        }
                        context.fill(path, with: paperShading)
                        context.stroke(path, with: paperShading, style: arm)
                    }
                }
                layer("ball", in: queep, t: t, unit: unit) { context, size in
                    context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: paperShading)
                }
            }
            layer("shape1", in: camera, t: t, unit: unit) { context, _ in fill("shape1", in: context, with: inkShading) }
            layer("shape2", in: camera, t: t, unit: unit) { context, size in
                context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: inkShading)
            }
            layer("shape3", in: camera, t: t, unit: unit) { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24.96), with: inkShading)
            }
            layer("shape4", in: camera, t: t, unit: unit) { context, _ in fill("shape4", in: context, with: inkShading) }
            layer("shape5", in: camera, t: t, unit: unit) { context, size in
                context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: inkShading)
            }
            layer("shape6", in: camera, t: t, unit: unit) { context, _ in fill("shape6", in: context, with: inkShading) }
            layer("shape7", in: camera, t: t, unit: unit) { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 21.6), with: inkShading)
            }
            layer("shape8", in: camera, t: t, unit: unit) { context, _ in fill("shape8", in: context, with: inkShading) }
        }
    }

    private func fill(_ name: String, in context: GraphicsContext, with shading: GraphicsContext.Shading) {
        guard let path = paths[name] else { return }
        context.fill(path, with: shading)
    }

    /// One Figma layer: CSS `translate`, `rotate` and `scale` around the layer's centre, then
    /// opacity and blur on the composited layer. `draw` works in the layer's own coordinates.
    private func layer(_ name: String, in parent: GraphicsContext, t: Double, unit: CGFloat,
                       draw: (GraphicsContext, CGSize) -> Void) {
        guard let frame = Self.frames[name] else { return }
        let keys = tracks[name] ?? [:]
        let opacity = value(keys["opacity"], t)?.first ?? 1
        guard opacity > 0.001 else { return }
        let height = CGFloat(value(keys["height"], t)?.first ?? Double(frame.height))
        let size = CGSize(width: frame.width, height: height)
        let move = value(keys["translate"], t) ?? [0, 0]
        let turn = value(keys["rotate"], t)?.first ?? 0
        let scale = value(keys["scale"], t) ?? [1, 1]
        let blur = value(keys["blur"], t)?.first ?? 0

        var context = parent
        context.translateBy(x: frame.minX + size.width / 2 + move[0], y: frame.minY + size.height / 2 + move[1])
        context.rotate(by: .radians(turn))
        context.scaleBy(x: scale[0], y: scale[1])
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        if opacity >= 0.999 && blur < 0.01 {
            draw(context, size)
            return
        }
        context.opacity *= opacity
        if blur >= 0.01 { context.addFilter(.blur(radius: blur * unit)) }
        context.drawLayer { layer in draw(layer, size) }
    }

    /// Linear interpolation between the two keys around `t`.
    private func value(_ track: [[Double]]?, _ t: Double) -> [Double]? {
        guard let track, let first = track.first, first.count > 1 else { return nil }
        if t <= first[0] || track.count == 1 { return Array(first.dropFirst()) }
        guard let last = track.last, t < last[0] else { return Array(track[track.count - 1].dropFirst()) }
        var low = 0
        var high = track.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if track[middle][0] <= t { low = middle } else { high = middle }
        }
        let a = track[low]
        let b = track[high]
        let span = b[0] - a[0]
        let f = span > 0 ? (t - a[0]) / span : 0
        return (1..<min(a.count, b.count)).map { a[$0] + (b[$0] - a[$0]) * f }
    }
}

/// Reads the absolute `M L H V C Z` path data that Figma exports.
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var current = CGPoint.zero

        func flush() {
            switch command {
            case "M":
                var index = 0
                while index + 1 < numbers.count {
                    let point = CGPoint(x: numbers[index], y: numbers[index + 1])
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    current = point
                    index += 2
                }
            case "L":
                var index = 0
                while index + 1 < numbers.count {
                    current = CGPoint(x: numbers[index], y: numbers[index + 1])
                    path.addLine(to: current)
                    index += 2
                }
            case "H":
                for x in numbers {
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                }
            case "V":
                for y in numbers {
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                }
            case "C":
                var index = 0
                while index + 5 < numbers.count {
                    let end = CGPoint(x: numbers[index + 4], y: numbers[index + 5])
                    path.addCurve(to: end,
                                  control1: CGPoint(x: numbers[index], y: numbers[index + 1]),
                                  control2: CGPoint(x: numbers[index + 2], y: numbers[index + 3]))
                    current = end
                    index += 6
                }
            case "Z", "z":
                path.closeSubpath()
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        for character in data {
            if character.isLetter && character != "e" && character != "E" {
                endNumber()
                flush()
                command = character
            } else if character == "-" && !token.isEmpty && token.last != "e" && token.last != "E" {
                endNumber()
                token.append(character)
            } else if character == "." && token.contains(".") && !token.contains("e") {
                endNumber()
                token.append(character)
            } else if character == " " || character == "," || character == "\n" || character == "\t" {
                endNumber()
            } else {
                token.append(character)
            }
        }
        endNumber()
        flush()
        return path
    }
}
