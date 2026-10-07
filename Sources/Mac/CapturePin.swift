import AppKit
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

/// Floating capture pin. It stays on screen, can be dragged anywhere, and opens a card on click.
@MainActor
@Observable
final class CapturePin {
    enum State: Equatable { case collapsed, expanded }

    private(set) var expanded = false
    private(set) var dragging = false
    private(set) var opensLeading = true
    var celebrating = false

    private var pinCenter = CGPoint.zero
    private var placed = false
    private var windowState = State.collapsed
    private var current = State.collapsed
    private var panel: NSPanel?
    private var outsideMonitors: [Any] = []
    private let capture: MacCapture

    private let pinSize = PinLayout.pin
    private let cardSize = PinLayout.card
    private let gap = PinLayout.gap
    private let shadowPad = PinLayout.shadowPad
    private let positionKey = "queep.pin.center"

    init(capture: MacCapture) { self.capture = capture }

    func update(enabled: Bool) {
        guard enabled, NSScreen.main != nil else {
            panel?.orderOut(nil); celebrating = false; setExpanded(false); return
        }
        if !placed { pinCenter = restore() ?? defaultCenter(); placed = true }
        pinCenter = clamp(pinCenter)
        if panel == nil { makePanel() }
        panel?.setFrame(frame(for: windowState), display: true)
        panel?.orderFrontRegardless()
    }

    /// Grows the window before the card appears so the pin stays where it was dropped.
    func prepare(for state: State) {
        current = state
        if state == .expanded {
            opensLeading = preferredOpensLeading()
            windowState = .expanded
            setFrame(frame(for: .expanded))
        }
    }

    /// Shrinks the window after the card has faded, so the rest of the screen stays clickable.
    func settle(_ state: State) {
        guard state == current else { return }
        windowState = state
        setFrame(frame(for: state))
    }

    func drag(to point: CGPoint) {
        dragging = true
        pinCenter = clamp(point)
        setFrame(frame(for: windowState))
    }

    func endDrag() {
        dragging = false
        persist()
    }

    /// Click toggles the card. A drag calls `endDrag` instead, so mouse-up after a move does not toggle.
    func toggle() {
        celebrating = false
        setExpanded(!expanded)
    }

    /// Forces the card shut after a save. It stays shut until the next click; pointer hover does not reopen it.
    func collapseForSave() {
        celebrating = true
        setExpanded(false)
    }

    func center() -> CGPoint { pinCenter }

    private func setExpanded(_ open: Bool) {
        expanded = open
        if open { installOutsideClickMonitors() } else { removeOutsideClickMonitors() }
    }

    /// Clicks on the pin and card are inside this rect. The shadow margin and the rest of the screen are outside.
    private func chromeFrame() -> CGRect? {
        guard let panel else { return nil }
        return panel.frame.insetBy(dx: shadowPad, dy: shadowPad)
    }

    private func closeIfOutside(_ point: CGPoint) {
        guard expanded, let chrome = chromeFrame(), !chrome.contains(point) else { return }
        setExpanded(false)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.closeIfOutside(point) }
            return event
        }) {
            outsideMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.closeIfOutside(point) }
        }) {
            outsideMonitors.append(monitor)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideMonitors.forEach(NSEvent.removeMonitor)
        outsideMonitors.removeAll()
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: frame(for: .collapsed), styleMask: [.borderless, .nonactivatingPanel],
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
        let host = NSHostingView(rootView: PinChrome().environment(capture).environment(capture.session)
            .environment(capture.library).environment(self))
        host.sizingOptions = []
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        // Shadows draw into the pad around the pin and card. Clipping the host
        // cuts them off, and a layer-backed ancestor flattens the backdrop blur.
        host.clipsToBounds = false
        panel.contentView = host
        panel.contentView?.clipsToBounds = false
        self.panel = panel
    }

    private func contentSize(for state: State) -> CGSize {
        switch state {
        case .collapsed: pinSize
        case .expanded: CGSize(width: cardSize.width + gap + pinSize.width, height: max(cardSize.height, pinSize.height))
        }
    }

    private func frame(for state: State) -> CGRect {
        let content = contentSize(for: state)
        let pinFromLeading: CGFloat = {
            guard state == .expanded, opensLeading else { return pinSize.width / 2 }
            return cardSize.width + gap + pinSize.width / 2
        }()
        let originX = pinCenter.x - shadowPad - pinFromLeading
        let originY = pinCenter.y - shadowPad - content.height / 2
        return CGRect(x: originX, y: originY, width: content.width + shadowPad * 2, height: content.height + shadowPad * 2)
    }

    private func setFrame(_ rect: CGRect) {
        panel?.setFrame(rect, display: true)
    }

    private func preferredOpensLeading() -> Bool {
        let screen = screen(containing: pinCenter)
        let visible = screen?.visibleFrame ?? .zero
        let needed = cardSize.width + gap
        let leading = pinCenter.x - pinSize.width / 2 - visible.minX
        let trailing = visible.maxX - (pinCenter.x + pinSize.width / 2)
        if leading >= needed, trailing < needed { return true }
        if trailing >= needed, leading < needed { return false }
        return leading >= trailing
    }

    private func defaultCenter() -> CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        return CGPoint(x: visible.maxX - 36, y: visible.midY)
    }

    private func restore() -> CGPoint? {
        guard let raw = UserDefaults.standard.string(forKey: positionKey) else { return nil }
        let parts = raw.split(separator: ",")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func persist() {
        UserDefaults.standard.set("\(pinCenter.x),\(pinCenter.y)", forKey: positionKey)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        guard let screen = screen(containing: point) ?? NSScreen.main else { return point }
        let visible = screen.visibleFrame.insetBy(dx: pinSize.width / 2 + 8, dy: pinSize.height / 2 + 8)
        return CGPoint(x: min(max(point.x, visible.minX), visible.maxX),
                       y: min(max(point.y, visible.minY), visible.maxY))
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -80, dy: -80).contains(point) }
    }
}

private struct PinDragSurface: NSViewRepresentable {
    var center: () -> CGPoint
    var move: (CGPoint) -> Void
    var end: () -> Void
    var click: () -> Void

    func makeNSView(context: Context) -> PinDragView {
        let view = PinDragView()
        view.centerProvider = center
        view.move = move
        view.end = end
        view.click = click
        return view
    }

    func updateNSView(_ nsView: PinDragView, context: Context) {
        nsView.centerProvider = center
        nsView.move = move
        nsView.end = end
        nsView.click = click
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PinDragView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: PinLayout.pin)
    }
}

private final class PinDragView: NSView {
    var centerProvider: () -> CGPoint = { .zero }
    var move: (CGPoint) -> Void = { _ in }
    var end: () -> Void = {}
    var click: () -> Void = {}
    private var originMouse: CGPoint?
    private var originCenter: CGPoint?
    private var dragged = false
    /// Movement below this is still a click. Past it, mouse-up only ends the drag.
    private let dragSlop: CGFloat = 4

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        originMouse = NSEvent.mouseLocation
        originCenter = centerProvider()
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let originMouse, let originCenter else { return }
        let mouse = NSEvent.mouseLocation
        let delta = CGPoint(x: mouse.x - originMouse.x, y: mouse.y - originMouse.y)
        guard hypot(delta.x, delta.y) >= dragSlop else { return }
        dragged = true
        move(CGPoint(x: originCenter.x + delta.x, y: originCenter.y + delta.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard originMouse != nil else { return }
        let wasDrag = dragged
        originMouse = nil
        originCenter = nil
        dragged = false
        if wasDrag { end() } else { click() }
    }
}

private enum Notice: Equatable { case saved, failed(String) }

private struct PinChrome: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(CapturePin.self) private var pin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = CapturePin.State.collapsed
    @State private var targeted = false
    @State private var notice: Notice?
    @State private var noticeTask: Task<Void, Never>?

    private var desired: CapturePin.State {
        if pin.dragging { return state }
        if pin.celebrating { return .collapsed }
        if pin.expanded || targeted { return .expanded }
        return .collapsed
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(alignment: .center, spacing: PinLayout.gap) {
            if state == .expanded, pin.opensLeading {
                PinCard(notice: notice, targeted: targeted).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            }
            PinMark(notice: notice)
            if state == .expanded, !pin.opensLeading {
                PinCard(notice: notice, targeted: targeted).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(PinLayout.shadowPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pin.opensLeading ? .trailing : .leading)
        .environment(\.colorScheme, .dark)
        .onDrop(of: [UTType.url, .image, .plainText, .movie, .audio], isTargeted: $targeted) { providers in
            capture.receive(providers, quietly: true); return true
        }
        .onChange(of: desired, initial: true) { _, next in transition(to: next) }
        .onChange(of: capture.message) { _, message in
            guard message == MacCapture.savedMessage else { return }
            flash(.saved, seconds: 3)
            if pin.expanded || targeted { pin.collapseForSave() }
        }
        .onChange(of: capture.error) { _, error in if let error { flash(.failed(error), seconds: 5) } }
        .onChange(of: state) { _, next in
            guard next == .expanded, !library.hasLoaded, let api = session.client(), let uid = session.userID else { return }
            Task { await library.refresh(api, account: uid) }
        }
    }

    private func transition(to next: CapturePin.State) {
        guard next != state else { return }
        pin.prepare(for: next)
        withAnimation(animation, completionCriteria: .logicallyComplete) { state = next } completion: { pin.settle(next) }
    }

    private func flash(_ value: Notice, seconds: Double) {
        noticeTask?.cancel()
        if value != .saved { pin.celebrating = false }
        notice = value
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
            if value == .saved { pin.celebrating = false }
        }
    }
}

private struct PinMark: View {
    @Environment(MacCapture.self) private var capture
    @Environment(CapturePin.self) private var pin
    let notice: Notice?

    var body: some View {
        Image("HomeLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(690 / 670, contentMode: .fit)
            .frame(width: 18.53, height: 18)
            .accessibilityHidden(true)
            .frame(width: PinLayout.pin.width, height: PinLayout.pin.height)
            .overlay(alignment: .bottom) {
                status
                    .padding(.bottom, 3)
                    .allowsHitTesting(false)
            }
            .overlay {
                PinDragSurface(center: { pin.center() }, move: { pin.drag(to: $0) }, end: { pin.endDrag() }, click: { pin.toggle() })
                    .accessibilityHidden(true)
            }
            .modifier(PinPlate(
                cornerRadius: 10,
                fillOpacity: PinLayout.pinFillOpacity,
                shadowRadius: 12,
                shadowY: 5,
                shadowOpacity: 0.40
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint("Arraste para mover. Clique para colar, capturar a tela ou abrir a biblioteca.")
            .accessibilityIdentifier("island")
    }

    private var label: String {
        if capture.busy { return "Salvando no Queep" }
        if case .failed = notice { return "Falha ao salvar no Queep" }
        if notice == .saved { return "Salvo no Queep" }
        return "Pin do Queep"
    }

    @ViewBuilder private var status: some View {
        if capture.busy {
            ProgressView().controlSize(.mini).scaleEffect(0.6)
        } else if case .failed = notice {
            Image(systemName: "exclamationmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.66, blue: 0.36))
        } else if notice == .saved {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(red: 0.67, green: 0.8, blue: 0.48))
        }
    }
}

private struct PinCard: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    let notice: Notice?
    let targeted: Bool

    private var latest: Reference? { library.items.first }
    private var canSave: Bool { session.userID != nil && !capture.busy && capture.pending == nil }

    private var title: String {
        if targeted { return "Solte para salvar" }
        if capture.busy { return "Salvando…" }
        if capture.pending != nil { return "Envio pendente" }
        if case .failed = notice { return "Não foi possível salvar" }
        if notice == .saved { return "Salvo" }
        if session.userID == nil { return "Entre para salvar" }
        if let latest { return latest.displayTitle }
        return "Queep"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image("HomeLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(690 / 670, contentMode: .fit)
                    .frame(width: 33.99, height: 33.02)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4.5) {
                    Text(title)
                        .font(.system(size: 9.756, weight: .bold))
                        .foregroundStyle(Color(red: 220 / 255, green: 220 / 255, blue: 220 / 255))
                        .lineLimit(1)
                    Button(action: openLast) {
                        HStack(spacing: 1.5) {
                            Text("Open last save")
                                .font(.system(size: 8.255))
                                .foregroundStyle(Color(red: 147 / 255, green: 145 / 255, blue: 143 / 255))
                            Image("PinOpenArrow")
                                .resizable()
                                .frame(width: 9.756, height: 9.756)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open last save")
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    PinAction("Create Note", asset: "PinEdit", id: "island.quick") { capture.show() }
                    PinAction("Clipboard", asset: "PinClipboard", id: "island.paste", disabled: !canSave) {
                        capture.paste(quietly: true)
                    }
                }
                HStack(spacing: 6) {
                    PinAction("Screenshot", asset: "PinScreenshot", id: "island.screenshot", disabled: !canSave) {
                        capture.captureScreen(quietly: true)
                    }
                    PinAction("Open Home", asset: "PinDashboard", id: "island.library") { capture.showLibrary() }
                }
            }
        }
        .padding(18)
        .frame(width: PinLayout.card.width, height: PinLayout.card.height, alignment: .topLeading)
        .modifier(PinPlate(
            cornerRadius: 24,
            fillOpacity: PinLayout.cardFillOpacity,
            shadowRadius: 18,
            shadowY: 8,
            shadowOpacity: 0.36
        ))
    }

    private func openLast() {
        capture.showLibrary()
        if let latest { library.presentation = .reference(latest) }
    }
}

private struct PinAction: View {
    let label: String
    let asset: String
    let id: String
    var disabled = false
    let action: () -> Void
    @State private var hovered = false

    init(_ label: String, asset: String, id: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.asset = asset; self.id = id; self.disabled = disabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(asset)
                    .resizable()
                    .frame(width: 15.009, height: 15.009)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 220 / 255, green: 220 / 255, blue: 220 / 255))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12.3)
            .frame(maxWidth: .infinity, minHeight: 34.52, maxHeight: 34.52, alignment: .leading)
            .background(Color(red: 57 / 255, green: 54 / 255, blue: 50 / 255), in: RoundedRectangle(cornerRadius: 12.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12.3, style: .continuous)
                    .strokeBorder(Color(red: 57 / 255, green: 54 / 255, blue: 50 / 255), lineWidth: 0.75)
            }
            .opacity(disabled ? 0.4 : hovered ? 0.82 : 1)
        }
        .buttonStyle(.plain).disabled(disabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(label).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

/// Shared pin geometry. `shadowPad` is the transparent margin inside the panel so
/// drop shadows are inside the window instead of clipped at its edge.
private enum PinLayout {
    static let pin = CGSize(width: 32, height: 38)
    static let card = CGSize(width: 350, height: 156)
    static let gap: CGFloat = 16
    static let shadowPad: CGFloat = 56
    /// #292521 over the backdrop blur. 0.9 hid the blur; this lets it read.
    static let pinFillOpacity: CGFloat = 0.55
    static let cardFillOpacity: CGFloat = 0.68
}

/// Frosted plate. The blur is not a child of the shadow: a shadow pass flattens
/// `NSVisualEffectView` and the nonactivating panel otherwise leaves the material inactive.
private struct PinPlate: ViewModifier {
    var cornerRadius: CGFloat
    var fillOpacity: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat
    var shadowOpacity: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                DesktopBlur(cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        shape.fill(Color(red: 41 / 255, green: 37 / 255, blue: 33 / 255).opacity(fillOpacity))
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(Color(red: 57 / 255, green: 54 / 255, blue: 50 / 255), lineWidth: 0.75)
                    }
                    .allowsHitTesting(false)
            }
            .background {
                shape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                    .allowsHitTesting(false)
            }
    }
}

/// Backdrop blur that stays active on a nonactivating panel. SwiftUI's material
/// follows window-active state, so on this panel it renders flat and looks hidden.
private struct DesktopBlur: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> ActiveDesktopBlurView {
        let view = ActiveDesktopBlurView()
        view.pinCornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: ActiveDesktopBlurView, context: Context) {
        view.pinCornerRadius = cornerRadius
        view.reveal()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActiveDesktopBlurView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

private final class ActiveDesktopBlurView: NSVisualEffectView {
    var pinCornerRadius: CGFloat = 0 {
        didSet { applyShape() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        reveal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        reveal()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reveal()
    }

    override func layout() {
        super.layout()
        reveal()
    }

    func reveal() {
        state = .active
        blendingMode = .behindWindow
        material = .popover
        isHidden = false
        alphaValue = 1
        applyShape()
    }

    private func applyShape() {
        layer?.cornerRadius = pinCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}
