import AppKit
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

/// Floating capture pin. It stays on screen, can be dragged anywhere, and opens a card on hover.
@MainActor
@Observable
final class CapturePin {
    enum State: Equatable { case collapsed, expanded }

    private(set) var hovering = false
    private(set) var dragging = false
    private(set) var opensLeading = true
    var celebrating = false

    private var pinCenter = CGPoint.zero
    private var placed = false
    private var windowState = State.collapsed
    private var current = State.collapsed
    private var panel: NSPanel?
    private var enterTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private let capture: MacCapture

    private let pinSize = CGSize(width: 52, height: 72)
    private let cardSize = CGSize(width: 328, height: 276)
    private let gap: CGFloat = 12
    private let shadowPad: CGFloat = 20
    private let positionKey = "queep.pin.center"

    init(capture: MacCapture) { self.capture = capture }

    func update(enabled: Bool) {
        guard enabled, NSScreen.main != nil else {
            panel?.orderOut(nil); celebrating = false; hovering = false; return
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
        enterTask?.cancel()
        pinCenter = clamp(point)
        setFrame(frame(for: windowState))
    }

    func endDrag() {
        dragging = false
        persist()
        if let panel, panel.frame.contains(NSEvent.mouseLocation) { hover(true) }
    }

    func center() -> CGPoint { pinCenter }

    private func hover(_ inside: Bool) {
        exitTask?.cancel()
        enterTask?.cancel()
        if inside {
            guard !celebrating, !dragging else { return }
            enterTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, let self, !self.dragging, !self.celebrating else { return }
                self.hovering = true
            }
            return
        }
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.hovering = false
            self?.celebrating = false
        }
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
        let tracking = HoverTrackingView(frame: panel.contentView?.bounds ?? .zero)
        tracking.onHover = { [weak self] inside in self?.hover(inside) }
        let host = NSHostingView(rootView: PinChrome().environment(capture).environment(capture.session)
            .environment(capture.library).environment(self))
        host.sizingOptions = []
        host.frame = tracking.bounds
        host.autoresizingMask = [.width, .height]
        tracking.addSubview(host)
        tracking.autoresizingMask = [.width, .height]
        panel.contentView = tracking
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

    func makeNSView(context: Context) -> PinDragView {
        let view = PinDragView()
        view.centerProvider = center
        view.move = move
        view.end = end
        return view
    }

    func updateNSView(_ nsView: PinDragView, context: Context) {
        nsView.centerProvider = center
        nsView.move = move
        nsView.end = end
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PinDragView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 52, height: 72))
    }
}

private final class PinDragView: NSView {
    var centerProvider: () -> CGPoint = { .zero }
    var move: (CGPoint) -> Void = { _ in }
    var end: () -> Void = {}
    private var originMouse: CGPoint?
    private var originCenter: CGPoint?

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        originMouse = NSEvent.mouseLocation
        originCenter = centerProvider()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let originMouse, let originCenter else { return }
        let mouse = NSEvent.mouseLocation
        move(CGPoint(x: originCenter.x + mouse.x - originMouse.x, y: originCenter.y + mouse.y - originMouse.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard originMouse != nil else { return }
        originMouse = nil
        originCenter = nil
        end()
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
        if pin.celebrating || pin.dragging { return pin.dragging ? state : .collapsed }
        if pin.hovering || targeted { return .expanded }
        return .collapsed
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if state == .expanded, pin.opensLeading {
                PinCard(notice: notice, targeted: targeted).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            }
            PinMark(notice: notice)
            if state == .expanded, !pin.opensLeading {
                PinCard(notice: notice, targeted: targeted).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pin.opensLeading ? .trailing : .leading)
        .environment(\.colorScheme, .dark)
        .onDrop(of: [UTType.url, .image, .plainText, .movie, .audio], isTargeted: $targeted) { providers in
            capture.receive(providers, quietly: true); return true
        }
        .onChange(of: desired, initial: true) { _, next in transition(to: next) }
        .onChange(of: capture.message) { _, message in
            guard message == MacCapture.savedMessage else { return }
            flash(.saved, seconds: 3)
            if pin.hovering || targeted { pin.celebrating = true }
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
        notice = value
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}

private struct PinMark: View {
    @Environment(MacCapture.self) private var capture
    @Environment(CapturePin.self) private var pin
    let notice: Notice?

    var body: some View {
        VStack(spacing: 5) {
            Image("HomeLogo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(690 / 670, contentMode: .fit)
                .frame(width: 30)
                .accessibilityHidden(true)
            status
        }
        .frame(width: 52, height: 72)
        .background(Color(red: 41 / 255, green: 37 / 255, blue: 33 / 255), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        .overlay {
            PinDragSurface(center: { pin.center() }, move: { pin.drag(to: $0) }, end: { pin.endDrag() })
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Arraste para mover. Passe o mouse para colar, capturar a tela ou abrir a biblioteca.")
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
            ProgressView().controlSize(.mini)
        } else if case .failed = notice {
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.66, blue: 0.36))
        } else if notice == .saved {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.67, green: 0.8, blue: 0.48))
        }
    }
}

private struct PinCard: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(CapturePin.self) private var pin
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

    private var preview: String {
        if targeted { return "Imagem, link, texto, áudio ou vídeo." }
        if capture.busy { return capture.message ?? "A análise continua na nuvem." }
        if capture.pending != nil { return capture.error ?? "Repita ou descarte na captura rápida." }
        if case .failed(let reason) = notice { return reason }
        if session.userID == nil { return "Abra a biblioteca e entre na sua conta." }
        if let latest {
            let body = latest.text.isEmpty ? (latest.transcript ?? latest.source?.text ?? "") : latest.text
            if !body.isEmpty { return body }
            return "\(latest.kindLabel) · \(latest.statusLabel)"
        }
        return "Solte algo aqui, cole o que está copiado ou capture a tela."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("HomeLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(690 / 670, contentMode: .fit)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    if let latest, !targeted, !capture.busy, notice == nil, capture.pending == nil {
                        Text("\(latest.kindLabel) · \(latest.statusLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(preview)
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.86, green: 0.84, blue: 0.8))
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 8) {
                PinAction("Captura rápida", symbol: "square.and.pencil", id: "island.quick") { capture.show() }
                PinAction("Colar e salvar", symbol: "doc.on.clipboard", id: "island.paste", disabled: !canSave) {
                    capture.paste(quietly: true)
                }
                PinAction("Capturar tela", symbol: "camera.viewfinder", id: "island.screenshot", disabled: !canSave) {
                    capture.captureScreen(quietly: true)
                }
                PinAction("Abrir biblioteca", symbol: "books.vertical.fill", id: "island.library") { capture.showLibrary() }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: 328, height: 276, alignment: .topLeading)
        .background(Color(red: 41 / 255, green: 37 / 255, blue: 33 / 255), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }
}

private struct PinAction: View {
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
                .frame(width: 32, height: 32)
                .background(.white.opacity(hovered && !disabled ? 0.22 : 0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(label).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}
