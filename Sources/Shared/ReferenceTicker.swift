import ImageIO
import Observation
import QueepCore
import SwiftUI

/// One tile of the entry ticker. It reads as something saved in Queep: a picture, the network
/// it came from and a hint of its kind. Pictures are bundled as `ticker-<name>.jpg`;
/// sources and licence are listed in `TICKER-IMAGES.md`.
struct TickerItem: Identifiable, Equatable, Sendable {
    let name: String
    /// Width over height of the bundled crop.
    let aspect: CGFloat
    var source: LinkSurface? = nil
    var glyph: String? = nil
    var id: String { name }
}

enum TickerCatalog {
    private static let reel = "play.fill"
    private static let carousel = "square.on.square"
    private static let link = "arrow.up.right"

    /// Ordered so that any split into lanes keeps subjects and shapes mixed.
    static let items: [TickerItem] = [
        TickerItem(name: "design-system", aspect: 3 / 4, source: .dribbble),
        TickerItem(name: "hibiscus", aspect: 2 / 3, source: .pinterest),
        TickerItem(name: "yellow-dress", aspect: 9 / 16, source: .instagram, glyph: reel),
        TickerItem(name: "geometric", aspect: 3 / 4, source: .dribbble),
        TickerItem(name: "stairs", aspect: 3 / 4, source: .pinterest),
        TickerItem(name: "glass-purple", aspect: 9 / 16, source: .twitter),
        TickerItem(name: "curves", aspect: 3 / 4, glyph: link),
        TickerItem(name: "app-orange", aspect: 3 / 4, source: .dribbble),
        TickerItem(name: "tulips", aspect: 2 / 3, source: .instagram),
        TickerItem(name: "blazer", aspect: 4 / 5, source: .instagram, glyph: carousel),
        TickerItem(name: "poster-science", aspect: 2 / 3, glyph: link),
        TickerItem(name: "palm-hotel", aspect: 4 / 5),
        TickerItem(name: "soft-layers", aspect: 3 / 4, source: .twitter),
        TickerItem(name: "dashboard", aspect: 4 / 5, source: .dribbble),
        TickerItem(name: "water", aspect: 1),
        TickerItem(name: "sneaker-orange", aspect: 1, source: .instagram),
        TickerItem(name: "chair-window", aspect: 2 / 3, source: .pinterest),
        TickerItem(name: "numeral", aspect: 4 / 5, source: .pinterest),
        TickerItem(name: "towers", aspect: 4 / 5, glyph: link),
        TickerItem(name: "wireframes", aspect: 9 / 16, source: .instagram, glyph: reel),
        TickerItem(name: "hands-sky", aspect: 3 / 4, source: .instagram),
        TickerItem(name: "streetwear", aspect: 9 / 16, source: .instagram, glyph: reel),
        TickerItem(name: "gradient-print", aspect: 3 / 4, source: .behance),
        TickerItem(name: "glass-grid", aspect: 4 / 5, source: .dribbble),
        TickerItem(name: "magazine", aspect: 3 / 4, glyph: link),
        TickerItem(name: "design-swatches", aspect: 4 / 5, source: .dribbble, glyph: carousel),
        TickerItem(name: "ceramics", aspect: 3 / 4, source: .pinterest),
        TickerItem(name: "sunglasses", aspect: 3 / 4),
        TickerItem(name: "arch", aspect: 4 / 5, source: .pinterest),
        TickerItem(name: "poster-exhibition", aspect: 2 / 3, glyph: link),
        TickerItem(name: "metal-waves", aspect: 9 / 16, source: .twitter),
        TickerItem(name: "concrete", aspect: 4 / 5, glyph: link),
        TickerItem(name: "app-dark", aspect: 4 / 5, source: .dribbble),
        TickerItem(name: "journal", aspect: 4 / 5, source: .pinterest),
        TickerItem(name: "sneakers-color", aspect: 4 / 5),
        TickerItem(name: "umbrellas", aspect: 3 / 4, source: .instagram),
        TickerItem(name: "copper", aspect: 3 / 4, source: .behance),
        TickerItem(name: "icon-set", aspect: 4 / 5, source: .dribbble),
        TickerItem(name: "jacket-truck", aspect: 4 / 5),
        TickerItem(name: "console", aspect: 1, source: .pinterest),
        TickerItem(name: "tower-dusk", aspect: 2 / 3),
        TickerItem(name: "app-gradients", aspect: 9 / 16, source: .dribbble, glyph: reel),
        TickerItem(name: "film-temple", aspect: 2 / 3),
        TickerItem(name: "brand-cards", aspect: 1, source: .behance)
    ]
}

/// Decodes the bundled pictures off the main thread, once, and frees them when no ticker is
/// on screen. Launch must not wait on forty JPEGs; tiles fade in when they are ready.
@MainActor @Observable
final class TickerImages {
    static let shared = TickerImages()

    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    func retain() {
        users += 1
        guard task == nil, images.isEmpty else { return }
        let names = TickerCatalog.items.map(\.name)
        task = Task { [weak self] in
            let decoded = await Self.decode(names)
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            guard self.users > 0 else { return }
            self.images = decoded.mapValues(\.image)
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        task?.cancel()
        task = nil
        images = [:]
    }

    /// `CGImage` is immutable once decoded; the wrapper only carries it across the task boundary.
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
    }

    nonisolated private static func decode(_ names: [String]) async -> [String: Decoded] {
        await withTaskGroup(of: (String, Decoded?).self) { group in
            for name in names {
                group.addTask(priority: .userInitiated) { (name, load(name)) }
            }
            var result: [String: Decoded] = [:]
            for await (name, image) in group { result[name] = image }
            return result
        }
    }

    nonisolated private static func load(_ name: String) -> Decoded? {
        guard let url = Bundle.main.url(forResource: "ticker-\(name)", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return Decoded(image: image)
    }
}

/// Lanes of saved-looking tiles drifting past, each at its own pace and direction.
/// Columns for the entry screens, rows for the paywall. Decorative: hidden from assistive
/// technologies and still when Reduce Motion is on.
struct ReferenceTicker: View {
    var axis: Axis = .vertical
    /// Lane count. Columns default to what the width holds, never fewer than three.
    var lanes: Int? = nil
    var gap: CGFloat = 10
    /// How far the outer columns run past the edges, so the grid reads as cropped, not fitted.
    var bleed: CGFloat = 14
    var radius: CGFloat = Theme.radius
    /// Points per second of the reference lane.
    var speed: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Starts some way into the loop, so each launch opens on a different arrangement.
    @State private var started = Date().addingTimeInterval(-Double.random(in: 0...900))

    var body: some View {
        GeometryReader { proxy in
            let plan = TickerPlan(size: proxy.size, axis: axis, lanes: lanes, gap: gap, bleed: bleed)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(started)
                ZStack(alignment: .topLeading) {
                    ForEach(plan.lanes) { lane in
                        let shift = lane.shift(elapsed: elapsed, speed: speed)
                        TickerLane(items: lane.items, axis: axis, cross: plan.cross, gap: gap,
                                   repeats: lane.repeats, radius: radius)
                            .equatable()
                            .offset(x: axis == .vertical ? lane.origin : shift,
                                    y: axis == .vertical ? shift : lane.origin)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { TickerImages.shared.retain() }
        .onDisappear { TickerImages.shared.release() }
    }
}

/// Where each lane sits and how its strip loops. Pure geometry, so the strip itself is only
/// laid out again when the size changes.
private struct TickerPlan {
    struct Lane: Identifiable {
        let id: Int
        let items: [TickerItem]
        /// Position across the ticker: x for a column, y for a row.
        let origin: CGFloat
        /// Length of one pass of the strip, trailing gap included.
        let period: CGFloat
        let repeats: Int
        /// Pace relative to `speed`. Negative lanes travel toward the start of the axis.
        let factor: CGFloat
        let phase: CGFloat

        func shift(elapsed: TimeInterval, speed: CGFloat) -> CGFloat {
            guard period > 0 else { return 0 }
            let travelled = (phase + CGFloat(elapsed) * speed * abs(factor))
                .truncatingRemainder(dividingBy: period)
            return factor < 0 ? -travelled : travelled - period
        }
    }

    private static let factors: [CGFloat] = [-1, 0.72, -1.18, 0.86, -0.94, 0.78, -1.1, 0.9]
    private static let phases: [CGFloat] = [0.12, 0.55, 0.31, 0.78, 0.05, 0.42, 0.66, 0.9]

    let cross: CGFloat
    let lanes: [Lane]

    init(size: CGSize, axis: Axis, lanes requested: Int?, gap: CGFloat, bleed: CGFloat) {
        let vertical = axis == .vertical
        let across = vertical ? size.width : size.height
        let along = vertical ? size.height : size.width
        let count = max(1, requested ?? max(3, Int((across / 190).rounded())))
        let overflow = vertical ? bleed : 0
        let cross = max(1, (across + overflow * 2 - gap * CGFloat(count - 1)) / CGFloat(count))
        self.cross = cross
        guard across > 1, along > 1 else {
            lanes = []
            return
        }
        lanes = (0..<count).map { index in
            let items = TickerCatalog.items.enumerated()
                .filter { $0.offset % count == index }
                .map(\.element)
            let period = items.reduce(CGFloat(0)) { total, item in
                total + (vertical ? cross / item.aspect : cross * item.aspect) + gap
            }
            let repeats = period > 0 ? Int((along / period).rounded(.up)) + 1 : 1
            return Lane(id: index, items: items,
                        origin: CGFloat(index) * (cross + gap) - overflow,
                        period: period, repeats: repeats,
                        factor: Self.factors[index % Self.factors.count],
                        phase: Self.phases[index % Self.phases.count] * period)
        }
    }
}

/// One strip, repeated enough to cover the lane while it loops. Equatable so the timeline's
/// ticks move it without laying its tiles out again.
private struct TickerLane: View, Equatable {
    let items: [TickerItem]
    let axis: Axis
    let cross: CGFloat
    let gap: CGFloat
    let repeats: Int
    let radius: CGFloat

    // Views are main-actor isolated; equality has to be callable from anywhere.
    nonisolated static func == (lhs: TickerLane, rhs: TickerLane) -> Bool {
        lhs.items == rhs.items && lhs.axis == rhs.axis && lhs.cross == rhs.cross
            && lhs.gap == rhs.gap && lhs.repeats == rhs.repeats && lhs.radius == rhs.radius
    }

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: gap)) : AnyLayout(HStackLayout(spacing: gap))
        layout {
            ForEach(0..<repeats, id: \.self) { _ in
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TickerTile(item: item, size: size(item), radius: radius,
                               delay: Double(index % 6) * 0.05)
                }
            }
        }
        .fixedSize()
    }

    private func size(_ item: TickerItem) -> CGSize {
        axis == .vertical
            ? CGSize(width: cross, height: cross / item.aspect)
            : CGSize(width: cross * item.aspect, height: cross)
    }
}

private struct TickerTile: View {
    let item: TickerItem
    let size: CGSize
    let radius: CGFloat
    let delay: Double

    /// Marks shrink with the tile so the paywall's short rows stay readable.
    private var mark: CGFloat { min(22, max(16, min(size.width, size.height) * 0.2)) }
    private var inset: CGFloat { mark * 0.36 }

    var body: some View {
        let image = TickerImages.shared.images[item.name]
        ZStack {
            Theme.fill
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let glyph = item.glyph {
                // A plain fill, not a material: a backdrop blur on every moving tile is costly.
                Image(systemName: glyph)
                    .font(.system(size: mark * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: mark, height: mark)
                    .background(Color.black.opacity(0.42), in: Circle())
                    .padding(inset)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let source = item.source {
                PostBrandMark(surface: source, size: mark, radius: mark * 0.3)
                    .overlay {
                        RoundedRectangle(cornerRadius: mark * 0.3, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    }
                    .padding(inset)
            }
        }
        .animation(.easeOut(duration: 0.45).delay(delay), value: image != nil)
    }
}
