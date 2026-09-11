import AppKit
import ScreenCaptureKit
import QueepCore

@MainActor
final class ScreenCapture {
    private(set) var active = false
    private var panels: [NSPanel] = []
    private var completion: ((Result<Data, Error>) -> Void)?
    private var generation = 0

    func start(completion: @escaping (Result<Data, Error>) -> Void) {
        guard !active else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            completion(.failure(QueepError.server("Permita a gravação de tela para o Queep em Ajustes do Sistema → Privacidade e Segurança. Depois tente capturar novamente.")))
            return
        }
        active = true
        generation += 1
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = false
            let selection = SelectionView(frame: .init(origin: .zero, size: screen.frame.size))
            selection.chosen = { [weak self] rect in self?.capture(rect, on: screen) }
            selection.cancelled = { [weak self] in self?.cancel() }
            panel.contentView = selection
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(selection)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissSelection() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    func cancel() { generation += 1; dismissSelection(); active = false; completion = nil }

    private func capture(_ area: CGRect, on screen: NSScreen) {
        guard active, let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { cancel(); return }
        dismissSelection()
        let scale = min(screen.backingScaleFactor, 4096 / max(area.width, area.height))
        let source = CGRect(x: area.minX, y: screen.frame.height - area.maxY, width: area.width, height: area.height)
        let operation = generation
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw QueepError.server("A tela mudou. Selecione a área novamente.")
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = source
                config.width = max(1, Int(area.width * scale))
                config.height = max(1, Int(area.height * scale))
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard active, generation == operation else { return }
                let bytes = try ImportedImage.encode(image).data
                finish(.success(bytes))
            } catch {
                guard active, generation == operation else { return }
                finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        let callback = completion
        completion = nil; active = false
        callback?(result)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class SelectionView: NSView {
    var chosen: ((CGRect) -> Void)?
    var cancelled: (() -> Void)?
    private var anchor: CGPoint?
    private var selection = CGRect.zero
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Captura de tela. Arraste para selecionar uma área. Enter captura esta tela. Escape cancela.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if selection.width >= 16 && selection.height >= 16 { chosen?(selection) }
        anchor = nil
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelled?()
        case 36, 76: chosen?(selection.width >= 16 && selection.height >= 16 ? selection : bounds)
        default: super.keyDown(with: event)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        let shade = NSBezierPath(rect: bounds)
        shade.windingRule = .evenOdd
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
        let text = "Arraste para capturar · Enter: tela inteira · Esc: cancelar"
        text.draw(at: .init(x: 24, y: bounds.height - 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white
        ])
    }
}
