import SwiftUI
import AppKit
import QuartzCore
import QueepCore

/// The library's bento masonry on a plane you drag like Figma's canvas, after ObsidianUI's art
/// gallery. A large library is endless: it repeats, seen through a soft barrel lens that moves and
/// scales each card instead of bending pixels, so clicks land where the card is drawn. A small
/// library, and every search, is one block with nothing repeated and the drag stops at its edges.
struct InfiniteBentoGallery<MenuContent: View>: View {
    let items: [Reference]
    /// Repeat the masonry in every direction. Off for search and for libraries under
    /// `InfiniteBentoPlan.endlessMinimum`, where copies read as duplicates.
    let endless: Bool
    /// Space covered by the floating bar and headings at the top of the plane.
    let topInset: CGFloat
    let more: Bool
    let loading: Bool
    let showsPromo: Bool
    let selecting: Bool
    let selectedIDs: Set<String>
    let open: (Reference) -> Void
    /// Nil where the gallery cannot select.
    var toggle: ((Reference) -> Void)?
    let promo: () -> Void
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = InfiniteGalleryMotion()

    var body: some View {
        GeometryReader { proxy in
            InfiniteBentoField(
                items: items,
                plan: InfiniteBentoPlan(items: items, promo: showsPromo, viewportWidth: proxy.size.width,
                                        endless: endless),
                viewport: proxy.size,
                topInset: topInset,
                motion: motion,
                reduceMotion: reduceMotion,
                selecting: selecting,
                selectedIDs: selectedIDs,
                open: open,
                toggle: toggle,
                promo: promo,
                menu: menu
            )
        }
        .background(InfiniteGalleryWindowReader(motion: motion))
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onChange(of: reduceMotion, initial: true) { _, reduce in motion.reduceMotion = reduce }
        .onChange(of: PrefetchState(count: items.count, more: more, loading: loading), initial: true) { _, state in
            // The plane has no end to reach, so the first pages load ahead of the hand.
            if state.more, !state.loading, state.count < InfiniteBentoPlan.prefetchLimit { loadMore() }
        }
        .onChange(of: motion.explorations) { _, _ in
            // Past the first pages, each stretch of exploring brings one more.
            if more, !loading { loadMore() }
        }
    }

    private struct PrefetchState: Equatable {
        let count: Int
        let more: Bool
        let loading: Bool
    }
}

/// Columns of the masonry. Endless, each column repeats on its own height so the plane has no
/// seams; otherwise the columns form one block centred on x = 0, starting at y = 0.
struct InfiniteBentoPlan {
    struct Tile {
        /// Index into the references, or nil for the PRO tile.
        let item: Int?
        let y: CGFloat
        let height: CGFloat
        /// First time this tile appears in the plan; the copies stay out of VoiceOver.
        let first: Bool
    }

    struct Slot: Identifiable, Equatable {
        let id: String
        let item: Int?
        let frame: CGRect
        let canonical: Bool
    }

    static let columnWidth: CGFloat = 264
    static let prefetchLimit = 240
    /// References a library needs before it repeats.
    static let endlessMinimum = 100

    let endless: Bool
    let columns: [[Tile]]
    let periods: [CGFloat]
    /// The block's frame when the plan is not endless.
    let content: CGRect

    var stride: CGFloat { Self.columnWidth + Theme.gap }

    @MainActor init(items: [Reference], promo: Bool, viewportWidth: CGFloat, endless: Bool) {
        let gap = Theme.gap
        self.endless = endless
        let count: Int
        if endless {
            let visible = Int(ceil(max(viewportWidth, 1) / InfiniteGalleryMotion.minimumScale / (Self.columnWidth + gap)))
            // Wider than the window, even zoomed out, so a column never meets its own copy on screen.
            count = max(4, visible + 3)
        } else {
            // As many columns as the window holds between its margins, never more than there are tiles.
            let room = max(1, viewportWidth - 2 * Theme.pageMargin(for: viewportWidth)) + gap
            count = max(1, min(Int(room / (Self.columnWidth + gap)), items.count + (promo ? 1 : 0)))
        }
        guard !items.isEmpty else {
            columns = []
            periods = []
            content = .zero
            return
        }
        var columns = Array(repeating: [Tile](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        func place(_ item: Int?, height: CGFloat, first: Bool) {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[column].append(Tile(item: item, y: heights[column], height: height, first: first))
            heights[column] += height + gap
        }
        if promo { place(nil, height: Self.columnWidth / PromoTile.aspect, first: true) }
        // Endless, few references are dealt out again so every column repeats without a pattern.
        let total = endless ? max(items.count, count * 5) : items.count
        for index in 0..<total {
            let item = index % items.count
            place(item, height: HomeReferenceCard.height(for: items[item], width: Self.columnWidth),
                  first: index < items.count)
        }
        self.columns = columns
        self.periods = heights
        let width = CGFloat(count) * (Self.columnWidth + gap) - gap
        content = CGRect(x: -width / 2, y: 0, width: width, height: max(0, (heights.max() ?? 0) - gap))
    }

    /// Tiles touching `rect`, in plane coordinates.
    func slots(in rect: CGRect) -> [Slot] {
        guard !columns.isEmpty else { return [] }
        var slots: [Slot] = []
        guard endless else {
            for (column, tiles) in columns.enumerated() {
                let x = content.minX + CGFloat(column) * stride
                for (row, tile) in tiles.enumerated() {
                    let frame = CGRect(x: x, y: tile.y, width: Self.columnWidth, height: tile.height)
                    guard frame.intersects(rect) else { continue }
                    slots.append(Slot(id: "\(column):0:\(row)", item: tile.item, frame: frame, canonical: true))
                }
            }
            return slots
        }
        let firstColumn = Int(floor(rect.minX / stride))
        let lastColumn = Int(floor(rect.maxX / stride))
        for world in firstColumn...lastColumn {
            let base = ((world % columns.count) + columns.count) % columns.count
            let period = periods[base]
            guard period > 0 else { continue }
            let x = CGFloat(world) * stride
            let firstCycle = Int(floor(rect.minY / period)) - 1
            let lastCycle = Int(floor(rect.maxY / period))
            for cycle in firstCycle...lastCycle {
                for (row, tile) in columns[base].enumerated() {
                    let y = CGFloat(cycle) * period + tile.y
                    guard y + tile.height >= rect.minY, y <= rect.maxY else { continue }
                    slots.append(Slot(
                        id: "\(world):\(cycle):\(row)",
                        item: tile.item,
                        frame: CGRect(x: x, y: y, width: Self.columnWidth, height: tile.height),
                        canonical: tile.first && cycle == 0 && world == base
                    ))
                }
            }
        }
        return slots
    }
}

private struct InfiniteBentoField<MenuContent: View>: View {
    let items: [Reference]
    let plan: InfiniteBentoPlan
    let viewport: CGSize
    let topInset: CGFloat
    let motion: InfiniteGalleryMotion
    let reduceMotion: Bool
    let selecting: Bool
    let selectedIDs: Set<String>
    let open: (Reference) -> Void
    let toggle: ((Reference) -> Void)?
    let promo: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent

    @State private var explored = false
    @State private var actions = PlaneActions<MenuContent>()

    /// A finite block keeps a page's margins: under the bar at the top, the page margin at the sides.
    private var limits: InfiniteGalleryLimits? {
        guard !plan.endless else { return nil }
        let side = Theme.pageMargin(for: viewport.width)
        return InfiniteGalleryLimits(content: plan.content, viewport: viewport,
                                     insets: EdgeInsets(top: topInset, leading: side, bottom: 72, trailing: side))
    }

    var body: some View {
        // Only this view reads the motion every frame. The tiles under it change when cards enter
        // or leave the window; moving and zooming the plane is one transform on top of them.
        let zoom = motion.zoom
        let offset = motion.offset
        let window = PlaneWindow(offset: offset, zoom: zoom, viewport: viewport)
        let _ = actions.update(open: open, toggle: toggle, promo: promo, menu: menu, motion: motion)
        PlaneTiles(items: items, slots: plan.slots(in: window.rect), near: window.anchor, viewport: viewport,
                   lens: plan.endless && !reduceMotion ? 0.08 : 0, selecting: selecting,
                   selectedIDs: selectedIDs, selectable: toggle != nil, actions: actions, motion: motion)
            .equatable()
            // While the plane moves, cards slide under a still pointer; hover would blink each one.
            .allowsHitTesting(!motion.moving)
            .offset(x: -offset.x, y: -offset.y)
            .scaleEffect(zoom, anchor: .center)
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .coordinateSpace(.named(PlaneSpace.name))
            .overlay {
                // The reference fades its corners into the background. A finite block keeps its edges.
                if plan.endless {
                    EllipticalGradient(colors: [Theme.surface.opacity(0), Theme.surface],
                                       center: .center, startRadiusFraction: 0.52, endRadiusFraction: 0.82)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                Text("Arraste para explorar")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.bottom, 22)
                    .opacity(explored || selecting || !plan.endless ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: explored || selecting)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                InfiniteGalleryZoomControl(motion: motion)
                    .padding(16)
            }
            .contentShape(Rectangle())
            .modifier(GrabCursor(dragging: motion.dragging))
            .onChange(of: motion.moved) { _, moved in if moved { explored = true } }
            .onChange(of: limits, initial: true) { _, limits in motion.setLimits(limits) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Biblioteca")
    }
}

private enum PlaneSpace {
    static let name = "infiniteBentoPlane"
}

/// The plane area worth building views for, snapped to a grid so it changes only when the hand
/// has travelled a step, not on every frame.
private struct PlaneWindow {
    let anchor: CGPoint
    let rect: CGRect

    init(offset: CGPoint, zoom: CGFloat, viewport: CGSize) {
        let step: CGFloat = 120
        anchor = CGPoint(x: (offset.x / step).rounded() * step, y: (offset.y / step).rounded() * step)
        // Zoom steps down, so the area is never smaller than what the window shows.
        let scale = max(InfiniteGalleryMotion.minimumScale, (zoom * 8).rounded(.down) / 8)
        // Cards are built a little outside the window, so they are ready before they show.
        let margin = step + 200
        let reach = CGSize(width: viewport.width / 2 / scale + margin, height: viewport.height / 2 / scale + margin)
        rect = CGRect(x: anchor.x - reach.width, y: anchor.y - reach.height,
                      width: reach.width * 2, height: reach.height * 2)
    }
}

/// The card callbacks in one stable object, so a new closure each frame does not count as a change
/// and rebuild every card.
@MainActor
private final class PlaneActions<MenuContent: View> {
    private(set) var open: (Reference) -> Void = { _ in }
    private(set) var toggle: ((Reference) -> Void)?
    private(set) var promo: () -> Void = {}
    private(set) var menu: ((Reference) -> MenuContent)?
    private(set) weak var motion: InfiniteGalleryMotion?

    func update(open: @escaping (Reference) -> Void, toggle: ((Reference) -> Void)?, promo: @escaping () -> Void,
                menu: @escaping (Reference) -> MenuContent, motion: InfiniteGalleryMotion) {
        self.open = open
        self.toggle = toggle
        self.promo = promo
        self.menu = menu
        self.motion = motion
    }

    /// False right after a drag: the release that ends it is not a click.
    func click() -> Bool { !(motion?.consumePan() ?? false) }
}

/// Cards at their plane positions, with the plane's origin at the centre of the window before the
/// plane's transform. Positions never depend on where the hand is, so a card already on screen is
/// left alone when others enter.
private struct PlaneTiles<MenuContent: View>: View, Equatable {
    let items: [Reference]
    let slots: [InfiniteBentoPlan.Slot]
    /// Plane point near the centre of the window, for choosing which loops play.
    let near: CGPoint
    let viewport: CGSize
    let lens: CGFloat
    let selecting: Bool
    let selectedIDs: Set<String>
    let selectable: Bool
    let actions: PlaneActions<MenuContent>
    let motion: InfiniteGalleryMotion

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.slots == rhs.slots && lhs.near == rhs.near && lhs.viewport == rhs.viewport
            && lhs.lens == rhs.lens && lhs.selecting == rhs.selecting && lhs.selectedIDs == rhs.selectedIDs
            && lhs.selectable == rhs.selectable && lhs.items == rhs.items
    }

    var body: some View {
        let centre = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let loops = loopSlots(centre: centre)
        let lens = lens
        let viewport = viewport
        ZStack(alignment: .topLeading) {
            ForEach(slots) { slot in
                tile(slot, playsLoop: loops.contains(slot.id))
                    .frame(width: slot.frame.width, height: slot.frame.height)
                    .position(x: slot.frame.midX + centre.x, y: slot.frame.midY + centre.y)
                    .modifier(PlaneLens(motion: motion, centre: CGPoint(x: slot.frame.midX, y: slot.frame.midY),
                                        viewport: viewport, strength: lens))
                    .accessibilityHidden(!slot.canonical)
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    @ViewBuilder private func tile(_ slot: InfiniteBentoPlan.Slot, playsLoop: Bool) -> some View {
        if let item = slot.item {
            let reference = items[item]
            PlaneCard(reference: reference, playsLoop: playsLoop, selectable: selectable,
                      selecting: selecting, selected: selectedIDs.contains(reference.id), actions: actions,
                      motion: motion)
                .equatable()
        } else {
            PromoTile { if actions.click() { actions.promo() } }
        }
    }

    /// The gallery's loop budget goes to the inline loops nearest the centre of the window.
    private func loopSlots(centre: CGPoint) -> Set<String> {
        let candidates = slots.compactMap { slot -> (id: String, distance: CGFloat)? in
            guard let item = slot.item, items[item].playsInlineLoop else { return nil }
            return (slot.id, hypot(slot.frame.midX - near.x, slot.frame.midY - near.y))
        }
        return Set(candidates.sorted { $0.distance < $1.distance }.prefix(InlineLoop.playerCap).map(\.id))
    }
}

/// Inverse of the reference's `uv * (1 - k r²)` sampling, to first order: cards drift outward and
/// grow with their distance from the centre of the window. Only this modifier reads the motion,
/// so a frame re-evaluates it and not the card under it. Drawn only; clicks use the card's place
/// before the lens.
private struct PlaneLens: ViewModifier {
    let motion: InfiniteGalleryMotion
    /// The card's centre on the plane.
    let centre: CGPoint
    let viewport: CGSize
    let strength: CGFloat

    func body(content: Content) -> some View {
        if strength > 0 {
            let zoom = motion.zoom
            let dx = (centre.x - motion.offset.x) * zoom
            let dy = (centre.y - motion.offset.y) * zoom
            let u = dx / max(viewport.width / 2, 1)
            let v = dy / max(viewport.height / 2, 1)
            let bulge = 1 + strength * (u * u + v * v)
            // Cards grow half as fast as they drift apart, so a tall card never reaches its neighbour.
            content
                .scaleEffect(1 + (bulge - 1) / 2)
                .offset(x: dx * (bulge - 1) / zoom, y: dy * (bulge - 1) / zoom)
        } else {
            content
        }
    }
}

/// One card on the plane. Compared by what it shows, so the closures it hands the cell, new on
/// every update, do not make SwiftUI rebuild it. A card that enters while the plane moves starts
/// as its picture alone and gets the full cell (button, menu, hover, badges) once the plane stops,
/// which keeps building cards out of the frames the hand is watching.
private struct PlaneCard<MenuContent: View>: View, Equatable {
    let reference: Reference
    let playsLoop: Bool
    let selectable: Bool
    let selecting: Bool
    let selected: Bool
    let actions: PlaneActions<MenuContent>
    let motion: InfiniteGalleryMotion

    @State private var full = false
    /// The picture stays under the full cell for a moment, so its image never flashes in empty.
    @State private var preview = true

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reference == rhs.reference && lhs.playsLoop == rhs.playsLoop && lhs.selectable == rhs.selectable
            && lhs.selecting == rhs.selecting && lhs.selected == rhs.selected
    }

    var body: some View {
        ZStack {
            if preview { picture }
            if full { cell }
        }
        .background {
            if !full {
                PlaneSettleWatcher(motion: motion) { full = true }
            }
        }
        .task(id: full) {
            guard full, preview else { return }
            try? await Task.sleep(for: .milliseconds(400))
            preview = false
        }
    }

    @ViewBuilder private var picture: some View {
        if reference.kind == "video" || !reference.gallery.isEmpty {
            Theme.fill
                .overlay(alignment: .top) { RemoteImage(reference: reference, thumbnail: true, fill: true) }
                .galleryTile()
                .accessibilityHidden(true)
        } else {
            HomeReferenceCard(reference: reference)
                .accessibilityHidden(true)
        }
    }

    private var cell: some View {
        let reference = reference
        let actions = actions
        return LibraryCardCell(reference: reference, playsLoop: playsLoop, selectable: selectable,
                               selecting: selecting, selected: selected,
                               open: { if actions.click() { actions.open(reference) } },
                               toggleSelection: { if actions.click() { actions.toggle?(reference) } }) {
            actions.menu?(reference)
        }
    }
}

/// Reads whether the plane is moving, so only this empty view, not the card, updates on it.
/// The plane must stay still for a moment: trackpad scrolling pauses between events, and swapping
/// cards in those gaps made them blink.
private struct PlaneSettleWatcher: View {
    let motion: InfiniteGalleryMotion
    let settled: () -> Void

    var body: some View {
        Color.clear
            .task(id: motion.moving) {
                guard !motion.moving else { return }
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, !motion.moving else { return }
                settled()
            }
    }
}

/// Where the plane is and how close. Dragging, scrolling and pinching follow the hand, like
/// Figma's hand, smoothed over a few frames of the display so uneven input does not judder;
/// the zoom buttons, the shortcuts and the trackpad's double tap ease a little longer.
@MainActor @Observable
final class InfiniteGalleryMotion {
    /// Plane point under the centre of the window.
    private(set) var offset = CGPoint.zero
    private(set) var zoom: CGFloat = 1
    /// Where `zoom` is heading; the control shows this one.
    private(set) var level: CGFloat = 1
    private(set) var dragging = false
    private(set) var moved = false
    /// True while the plane is catching up with the hand or a zoom.
    private(set) var moving = false
    /// Counts each long stretch of panning, so the gallery can load another page.
    private(set) var explorations = 0

    nonisolated static let minimumScale: CGFloat = 0.5
    nonisolated static let maximumScale: CGFloat = 2

    @ObservationIgnored var reduceMotion = false
    /// The gallery's own view: tells its window from sheets, and places the cursor.
    @ObservationIgnored weak var view: NSView?
    @ObservationIgnored private var target = CGPoint.zero
    @ObservationIgnored private var limits: InfiniteGalleryLimits?
    /// Plane distance panned since the last exploration.
    @ObservationIgnored private var travelled: CGFloat = 0
    /// Runs only while the plane is catching up with the hand, in step with the display.
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    @ObservationIgnored private var ease = InfiniteGalleryMotion.handEase
    @ObservationIgnored private lazy var ticker = DisplayTicker { [weak self] time in self?.tick(at: time) }
    @ObservationIgnored private var monitor: Any?
    /// Mouse-down point while the button is held over the gallery.
    @ObservationIgnored private var press: CGPoint?
    @ObservationIgnored private var lastPoint = CGPoint.zero
    /// Set when a drag ends, so the card under the pointer does not open on release.
    @ObservationIgnored private var panned = false

    /// Share of the remaining distance covered per 60 Hz frame. The hand's is short enough that the
    /// plane stops with it (about 70 ms); the zoom buttons glide a little.
    private static let handEase: CGFloat = 0.5
    private static let zoomEase: CGFloat = 0.28
    private static let zoomStep: CGFloat = 1.25
    /// Movement before a press becomes a drag, so a click still opens a card.
    private static let dragSlop: CGFloat = 3
    /// Plane distance that counts as one stretch of exploring.
    private static let explorationStretch: CGFloat = 1_600
    /// Corner kept for the zoom control: a press there never pans.
    private static let controlZone = CGSize(width: 160, height: 64)

    func start() {
        guard monitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.scrollWheel, .magnify, .smartMagnify,
                                             .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sleep()
    }

    /// True once after a drag: the click that ends it is not a click on a card.
    func consumePan() -> Bool {
        defer { panned = false }
        return panned
    }

    /// Nil lets the plane go anywhere; otherwise the content stays within the window's insets.
    func setLimits(_ limits: InfiniteGalleryLimits?) {
        guard limits != self.limits else { return }
        self.limits = limits
        target = clamped(target, zoom: level)
        offset = target
    }

    func zoomIn() { zoom(by: Self.zoomStep, at: .zero, eased: true) }
    func zoomOut() { zoom(by: 1 / Self.zoomStep, at: .zero, eased: true) }
    func resetZoom() { zoom(by: 1 / level, at: .zero, eased: true) }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // A drag that started here keeps going even if the pointer leaves the window.
        if event.type == .leftMouseDragged || event.type == .leftMouseUp, press != nil {
            return mouse(event)
        }
        guard let view, let window = view.window, event.window === window,
              window.attachedSheet == nil else { return event }
        let point = location(of: event, in: view)
        let anchor = CGPoint(x: point.x - view.bounds.width / 2, y: point.y - view.bounds.height / 2)
        switch event.type {
        case .leftMouseDown:
            guard view.bounds.contains(point), !inControlZone(point, of: view.bounds.size) else { return event }
            press = point
            lastPoint = point
            panned = false
            return event
        case .magnify:
            zoom(by: 1 + event.magnification, at: anchor, eased: false)
        case .smartMagnify:
            zoom(by: level < 1.2 ? 1.6 / level : 1 / level, at: anchor, eased: true)
        case .scrollWheel:
            let precise = event.hasPreciseScrollingDeltas
            if event.modifierFlags.contains(.command) {
                zoom(by: exp(event.scrollingDeltaY * (precise ? 0.01 : 0.1)), at: anchor, eased: false)
            } else {
                let step: CGFloat = precise ? 1 : 12
                pan(by: CGSize(width: event.scrollingDeltaX * step, height: event.scrollingDeltaY * step))
            }
        default:
            return event
        }
        return nil
    }

    private func mouse(_ event: NSEvent) -> NSEvent? {
        guard let view, let press else { return event }
        let point = location(of: event, in: view)
        if event.type == .leftMouseUp {
            if dragging { panned = true }
            dragging = false
            self.press = nil
            return event
        }
        if !dragging, hypot(point.x - press.x, point.y - press.y) > Self.dragSlop {
            dragging = true
        }
        if dragging {
            pan(by: CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y))
        }
        lastPoint = point
        return event
    }

    /// Moves the plane with the hand.
    private func pan(by delta: CGSize) {
        let previous = target
        target = clamped(CGPoint(x: target.x - delta.width / level, y: target.y - delta.height / level), zoom: level)
        ease = Self.handEase
        wake()
        travelled += hypot(target.x - previous.x, target.y - previous.y)
        if travelled > Self.explorationStretch {
            travelled = 0
            explorations += 1
        }
        if !moved, travelled > 24 || explorations > 0 { moved = true }
    }

    /// `anchor` is measured from the centre of the gallery; the plane point under it stays put.
    private func zoom(by factor: CGFloat, at anchor: CGPoint, eased: Bool) {
        let next = min(Self.maximumScale, max(Self.minimumScale, level * factor))
        guard next != level else { return }
        target.x += anchor.x / level - anchor.x / next
        target.y += anchor.y / level - anchor.y / next
        target = clamped(target, zoom: next)
        level = next
        ease = eased ? Self.zoomEase : Self.handEase
        wake()
    }

    /// Keeps a finite block inside the window. Narrower than the window, it centres across;
    /// shorter, it sits at the top, like a page.
    private func clamped(_ point: CGPoint, zoom: CGFloat) -> CGPoint {
        guard let limits else { return point }
        func axis(_ value: CGFloat, low edge: CGFloat, high end: CGFloat, lead: CGFloat, trail: CGFloat,
                  span: CGFloat, centres: Bool) -> CGFloat {
            let low = edge - lead / zoom + span / (2 * zoom)
            let high = end + trail / zoom - span / (2 * zoom)
            if low <= high { return min(max(value, low), high) }
            return centres ? (low + high) / 2 : low
        }
        let content = limits.content
        let insets = limits.insets
        return CGPoint(
            x: axis(point.x, low: content.minX, high: content.maxX, lead: insets.leading, trail: insets.trailing,
                    span: limits.viewport.width, centres: true),
            y: axis(point.y, low: content.minY, high: content.maxY, lead: insets.top, trail: insets.bottom,
                    span: limits.viewport.height, centres: false))
    }

    /// Event location in the gallery, from its top-left corner.
    private func location(of event: NSEvent, in view: NSView) -> CGPoint {
        let point = view.convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
    }

    private func inControlZone(_ point: CGPoint, of size: CGSize) -> Bool {
        point.x > size.width - Self.controlZone.width && point.y > size.height - Self.controlZone.height
    }

    private func wake() {
        if reduceMotion {
            offset = target
            zoom = level
            return
        }
        guard link == nil else { return }
        guard let view else {
            offset = target
            zoom = level
            return
        }
        let link = view.displayLink(target: ticker, selector: #selector(DisplayTicker.fire(_:)))
        link.add(to: .main, forMode: .common)
        lastTick = nil
        self.link = link
        moving = true
    }

    private func sleep() {
        link?.invalidate()
        link = nil
        if moving { moving = false }
    }

    private func tick(at time: CFTimeInterval) {
        let elapsed = lastTick.map { min(0.1, max(0, time - $0)) } ?? 1.0 / 60
        lastTick = time
        let share = 1 - pow(1 - ease, CGFloat(elapsed) * 60)
        offset.x += (target.x - offset.x) * share
        offset.y += (target.y - offset.y) * share
        zoom += (level - zoom) * share
        if abs(target.x - offset.x) < 0.05 && abs(target.y - offset.y) < 0.05 && abs(level - zoom) < 0.0005 {
            offset = target
            zoom = level
            sleep()
        }
    }
}

/// Target for the display link, which needs an Objective-C object. The link is added to the main
/// run loop, so it always fires on the main thread.
@MainActor
private final class DisplayTicker: NSObject {
    private let handler: @MainActor (CFTimeInterval) -> Void

    init(_ handler: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ link: CADisplayLink) {
        handler(link.targetTimestamp)
    }
}

struct InfiniteGalleryLimits: Equatable {
    var content: CGRect
    var viewport: CGSize
    var insets: EdgeInsets
}

private struct GrabCursor: ViewModifier {
    let dragging: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(dragging ? .grabActive : .grabIdle)
        } else {
            content
        }
    }
}

/// Fixed bottom-right: zoom out, the current level (click for 100%), zoom in. ⌘−, ⌘0 and ⌘= do the same.
private struct InfiniteGalleryZoomControl: View {
    let motion: InfiniteGalleryMotion

    private static let control: CGFloat = 28
    private static let inset: CGFloat = 4
    private static let radius: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            button("ri-subtract-line", label: "Diminuir zoom", key: "-", enabled: motion.level > InfiniteGalleryMotion.minimumScale) {
                motion.zoomOut()
            }
            Button(action: motion.resetZoom) {
                Text("\(Int((motion.level * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: Self.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZoomControlStyle())
            .keyboardShortcut("0", modifiers: .command)
            .help("Voltar para 100%")
            .accessibilityLabel("Zoom em \(Int((motion.level * 100).rounded())) por cento")
            .accessibilityHint("Volta para 100%")
            button("ri-add-line", label: "Aumentar zoom", key: "=", enabled: motion.level < InfiniteGalleryMotion.maximumScale) {
                motion.zoomIn()
            }
        }
        .padding(Self.inset)
        .floatingSurface(radius: Self.radius + Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.zoom")
    }

    private func button(_ asset: String, label: String, key: KeyEquivalent, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            QueepIcon(asset, size: 15, color: Theme.ink)
                .frame(width: Self.control, height: Self.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(ZoomControlStyle())
        .keyboardShortcut(key, modifiers: .command)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Fill under the pointer or a press, as the chrome's controls do.
private struct ZoomControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Theme.fillPressed : hovered ? Theme.fill : .clear)
            }
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovered = $0 && enabled }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Lets the event monitor tell this window's events from sheets and other windows.
private struct InfiniteGalleryWindowReader: NSViewRepresentable {
    let motion: InfiniteGalleryMotion

    func makeNSView(context: Context) -> NSView { WindowView(motion: motion) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowView: NSView {
        let motion: InfiniteGalleryMotion

        init(motion: InfiniteGalleryMotion) {
            self.motion = motion
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            motion.view = self
        }
    }
}
