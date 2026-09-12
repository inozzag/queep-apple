import AppKit
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

/// Dynamic-island style panel anchored to the notch, or to the top of a screen without one.
/// Collapsed it hides behind the hardware notch; hovering or dragging content over it opens it.
@MainActor
@Observable
final class NotchIsland {
    enum State: Equatable { case collapsed, compact, expanded }

    private(set) var hovering = false
    private(set) var hasNotch = false
    private(set) var notch = CGSize(width: 120, height: 12)
    var thumbnails: [String: Data] = [:]
    private var top: CGFloat = 0
    private var centerX: CGFloat = 0
    private var panel: NSPanel?
    private var current = State.collapsed
    private var exitTask: Task<Void, Never>?
    private let capture: MacCapture

    init(capture: MacCapture) { self.capture = capture }

    var contentTop: CGFloat { hasNotch ? notch.height : 10 }

    func size(for state: State) -> CGSize {
        switch state {
        case .collapsed: notch
        case .compact: hasNotch ? CGSize(width: notch.width + 208, height: notch.height) : CGSize(width: 232, height: 30)
        case .expanded: CGSize(width: 460, height: contentTop + 88)
        }
    }

    func radii(for state: State) -> (top: CGFloat, bottom: CGFloat) {
        switch state {
        case .collapsed: (0, hasNotch ? 14 : 6)
        case .compact: (8, 14)
        case .expanded: (18, 26)
        }
    }

    /// Shows or hides the panel and follows the notch screen whenever the screens change.
    func update(enabled: Bool) {
        guard enabled, measure() else { panel?.orderOut(nil); hover(false); return }
        if panel == nil { makePanel() }
        panel?.setFrame(frame(for: size(for: current)), display: true)
        panel?.orderFrontRegardless()
    }

    /// Grows the window before the shape animates so the island is never clipped.
    func prepare(for state: State) {
        let from = size(for: current), to = size(for: state)
        current = state
        panel?.setFrame(frame(for: CGSize(width: max(from.width, to.width), height: max(from.height, to.height))), display: true)
    }

    /// Shrinks the window after the animation so the menu bar beside the notch stays clickable.
    func settle(_ state: State) {
        guard state == current else { return }
        panel?.setFrame(frame(for: size(for: state)), display: true)
    }

    private func measure() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return false }
        hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: max(120, right.minX - left.maxX), height: screen.safeAreaInsets.top)
            centerX = (left.maxX + right.minX) / 2
            top = screen.frame.maxY
        } else if hasNotch {
            notch = CGSize(width: 180, height: screen.safeAreaInsets.top)
            centerX = screen.frame.midX
            top = screen.frame.maxY
        } else {
            notch = CGSize(width: 120, height: 12)
            centerX = screen.frame.midX
            top = screen.visibleFrame.maxY
        }
        return true
    }

    private func frame(for size: CGSize) -> CGRect {
        CGRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: frame(for: notch), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.identifier = .init("island")
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        let tracking = HoverTrackingView(frame: .init(origin: .zero, size: notch))
        tracking.onHover = { [weak self] inside in self?.hover(inside) }
        let host = NSHostingView(rootView: IslandView().environment(capture).environment(capture.session)
            .environment(capture.library).environment(self))
        host.sizingOptions = []
        host.frame = tracking.bounds
        host.autoresizingMask = [.width, .height]
        tracking.addSubview(host)
        panel.contentView = tracking
        self.panel = panel
    }

    private func hover(_ inside: Bool) {
        exitTask?.cancel()
        if inside { hovering = true; return }
        // A short grace period keeps the island open while the pointer crosses its edge.
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.hovering = false
        }
    }
}

private final class HoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        super.updateTrackingAreas()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The notch silhouette: concave ears that merge with the screen edge and convex bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0.01, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0.01, min(bottomRadius, rect.width / 2 - top, rect.height - top))
        var path = Path()
        path.move(to: .init(x: rect.minX, y: rect.minY))
        path.addArc(tangent1End: .init(x: rect.minX + top, y: rect.minY),
                    tangent2End: .init(x: rect.minX + top, y: rect.minY + top), radius: top)
        path.addLine(to: .init(x: rect.minX + top, y: rect.maxY - bottom))
        path.addArc(tangent1End: .init(x: rect.minX + top, y: rect.maxY),
                    tangent2End: .init(x: rect.minX + top + bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: .init(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addArc(tangent1End: .init(x: rect.maxX - top, y: rect.maxY),
                    tangent2End: .init(x: rect.maxX - top, y: rect.maxY - bottom), radius: bottom)
        path.addLine(to: .init(x: rect.maxX - top, y: rect.minY + top))
        path.addArc(tangent1End: .init(x: rect.maxX - top, y: rect.minY),
                    tangent2End: .init(x: rect.maxX, y: rect.minY), radius: top)
        path.closeSubpath()
        return path
    }
}

private enum Notice: Equatable { case saved, failed(String) }

private struct IslandView: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(NotchIsland.self) private var island
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = NotchIsland.State.collapsed
    @State private var targeted = false
    @State private var notice: Notice?
    @State private var noticeTask: Task<Void, Never>?

    private var desired: NotchIsland.State {
        if island.hovering || targeted { return .expanded }
        if capture.busy || notice != nil { return .compact }
        return .collapsed
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.76)
    }

    var body: some View {
        let size = island.size(for: state)
        let radii = island.radii(for: state)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        ZStack(alignment: .top) {
            shape.fill(.black)
            content.transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .onDrop(of: [UTType.url, .image, .plainText, .movie, .audio], isTargeted: $targeted) { providers in
            capture.receive(providers, quietly: true); return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: desired, initial: true) { _, next in transition(to: next) }
        .onChange(of: capture.message) { _, message in if message == MacCapture.savedMessage { flash(.saved, seconds: 3) } }
        .onChange(of: capture.error) { _, error in if let error { flash(.failed(error), seconds: 5) } }
        .onChange(of: state) { _, next in
            guard next == .expanded, !library.hasLoaded, let api = session.client(), let uid = session.userID else { return }
            Task { await library.refresh(api, account: uid) }
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .collapsed:
            Color.clear
                .accessibilityElement()
                .accessibilityLabel("Ilha do Queep")
                .accessibilityHint("Passe o mouse ou solte um arquivo para abrir as ações de captura")
                .accessibilityIdentifier("island")
        case .compact:
            CompactStatus(notice: notice)
        case .expanded:
            ExpandedPanel(notice: notice, targeted: targeted)
        }
    }

    private func transition(to next: NotchIsland.State) {
        guard next != state else { return }
        island.prepare(for: next)
        withAnimation(animation, completionCriteria: .logicallyComplete) { state = next } completion: { island.settle(next) }
    }

    private func flash(_ value: Notice, seconds: Double) {
        noticeTask?.cancel()
        notice = value
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}

private struct CompactStatus: View {
    @Environment(MacCapture.self) private var capture
    @Environment(NotchIsland.self) private var island
    let notice: Notice?

    private var label: String {
        if capture.busy { return "Salvando…" }
        if case .failed = notice { return "Falhou" }
        return "Salvo"
    }

    var body: some View {
        if island.hasNotch {
            HStack(spacing: 0) {
                StatusSymbol(notice: notice).frame(width: 104, height: island.notch.height)
                Color.clear.frame(width: island.notch.width, height: island.notch.height)
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).frame(width: 104, height: island.notch.height)
            }
        } else {
            HStack(spacing: 8) { StatusSymbol(notice: notice); Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
                .frame(height: 30)
        }
    }
}

private struct StatusSymbol: View {
    @Environment(MacCapture.self) private var capture
    let notice: Notice?

    var body: some View {
        if capture.busy {
            ProgressView().controlSize(.small)
        } else if case .failed = notice {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 1, green: 0.66, blue: 0.36))
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.36, green: 0.85, blue: 0.5))
        }
    }
}

private struct ExpandedPanel: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(NotchIsland.self) private var island
    let notice: Notice?
    let targeted: Bool

    private var latest: Reference? { library.items.first }
    private var canSave: Bool { session.userID != nil && !capture.busy && capture.pending == nil }

    private var headline: (title: String, detail: String, warning: Bool) {
        if targeted { return ("Solte para salvar", "Imagem, link, texto, áudio ou vídeo", false) }
        if capture.busy { return (capture.message ?? "Salvando…", "A análise continua na nuvem", false) }
        if capture.pending != nil { return ("Envio pendente", capture.error ?? "Repita ou descarte na captura rápida", true) }
        if case .failed(let reason) = notice { return ("Não foi possível salvar", reason, true) }
        if notice == .saved { return ("Salvo no Queep", "Análise em segundo plano", false) }
        if session.userID == nil { return ("Queep", "Entre na biblioteca para salvar", false) }
        if let latest {
            let context = latest.title.isEmpty ? "Última referência" : latest.kindLabel
            return (latest.displayTitle, "\(context) · \(latest.statusLabel)", false)
        }
        return ("Queep", "Solte, cole ou capture para salvar", false)
    }

    var body: some View {
        let line = headline
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                IslandThumbnail(reference: latest, notice: notice, targeted: targeted).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(line.detail).font(.system(size: 11))
                        .foregroundStyle(line.warning ? Color(red: 1, green: 0.66, blue: 0.36) : .white.opacity(0.62)).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    IslandAction("Captura rápida", symbol: "square.and.pencil", id: "island.quick") { capture.show() }
                    IslandAction("Colar e salvar", symbol: "doc.on.clipboard", id: "island.paste", disabled: !canSave) {
                        capture.paste(quietly: true)
                    }
                    IslandAction("Capturar tela", symbol: "camera.viewfinder", id: "island.screenshot", disabled: !canSave) {
                        capture.captureScreen(quietly: true)
                    }
                    IslandAction("Abrir biblioteca", symbol: "books.vertical.fill", id: "island.library") { capture.showLibrary() }
                }
            }
            ProgressTrack(busy: capture.busy, done: notice == .saved && !capture.busy)
        }
        .padding(.horizontal, 16 + island.radii(for: .expanded).top).padding(.top, island.contentTop + 10).padding(.bottom, 13)
        .frame(width: island.size(for: .expanded).width, alignment: .top)
    }
}

private struct IslandAction: View {
    let label: String
    let symbol: String
    let id: String
    var disabled = false
    let action: () -> Void
    @State private var hovered = false

    init(_ label: String, symbol: String, id: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.symbol = symbol; self.id = id; self.disabled = disabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
                .frame(width: 30, height: 30)
                .background(.white.opacity(hovered && !disabled ? 0.26 : 0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(label).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

private struct IslandThumbnail: View {
    @Environment(Session.self) private var session
    @Environment(MacCapture.self) private var capture
    @Environment(NotchIsland.self) private var island
    let reference: Reference?
    let notice: Notice?
    let targeted: Bool

    private var overlaySymbol: String? {
        if targeted { return "arrow.down.circle.fill" }
        if capture.busy { return nil }
        if case .failed = notice { return "exclamationmark.triangle.fill" }
        if notice == .saved { return "checkmark.circle.fill" }
        return nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(
                colors: [Color(hue: 0.60, saturation: 0.55, brightness: 0.62), Color(hue: 0.78, saturation: 0.55, brightness: 0.36)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            if let reference, let data = island.thumbnails[reference.id], let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: reference?.kindSymbol ?? "bookmark.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            }
            if capture.busy || overlaySymbol != nil {
                Color.black.opacity(0.45)
                if capture.busy { ProgressView().controlSize(.small) }
                else if let overlaySymbol { Image(systemName: overlaySymbol).font(.system(size: 22)).foregroundStyle(.white) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: "\(session.userID ?? "")/\(reference?.id ?? "")") {
            guard let reference, island.thumbnails[reference.id] == nil,
                  reference.image != nil || reference.kind == "video",
                  let api = session.client(), let uid = session.userID else { return }
            guard let bytes = try? await (reference.media == nil ? api.imageData(reference, thumbnail: true)
                                          : api.mediaData(reference, thumbnail: true)),
                  !Task.isCancelled, uid == session.userID else { return }
            island.thumbnails[reference.id] = bytes
        }
    }
}

private struct ProgressTrack: View {
    let busy: Bool
    let done: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                if busy {
                    Capsule().fill(.white.opacity(0.9)).frame(width: geometry.size.width * 0.28)
                        .phaseAnimator([false, true]) { view, moved in
                            view.offset(x: moved ? geometry.size.width * 0.72 : 0)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                } else if done {
                    Capsule().fill(Color(red: 0.36, green: 0.85, blue: 0.5))
                        .transition(.scale(scale: 0, anchor: .leading))
                }
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.4), value: done)
        .accessibilityHidden(true)
    }
}
