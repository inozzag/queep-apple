import AppKit
import Observation
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MacCapture {
    static let shared = MacCapture()
    static let savedMessage = "Salvo · análise em segundo plano"
    let session = Session()
    let library = LibraryStore()
    var draft = ""
    var captureSpaceID: String?
    var busy = false
    var message: String?
    var error: String?
    var pending: IncomingReference?
    var shortcutIssues: [String] = []
    /// Set by the library window so the pin can reopen it through SwiftUI's scene.
    var openLibrary: (() -> Void)?
    var pinEnabled = UserDefaults.standard.object(forKey: "queep.shelf.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pinEnabled, forKey: "queep.shelf.enabled"); pin?.update(enabled: pinEnabled) }
    }
    /// Pin-initiated flows report progress on the pin; failures still open the quick panel.
    private var quiet = false
    private var pendingSource = "shortcut"
    private var owner: String?
    private var quick: NSPanel?
    private var pin: CapturePin?
    private var screenObserver: NSObjectProtocol?
    private let screenshot = ScreenCapture()

    init() {
        session.onAccountChange = { [weak self] in
            guard let self else { return }
            draft = ""; pending = nil; owner = nil; error = nil; message = nil; quiet = false
            captureSpaceID = nil
            screenshot.cancel()
            library.reset(for: session.userID)
        }
    }

    func install() {
        pin = CapturePin(capture: self)
        pin?.update(enabled: pinEnabled)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.pin?.update(enabled: self?.pinEnabled ?? false) } }
    }

    func show() {
        if quick == nil {
            let panel = CapturePanel(contentRect: .init(x: 0, y: 0, width: 420, height: 320),
                                     styleMask: [.titled, .closable, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.title = "Salvar no Queep"
            panel.identifier = .init("quickCapture")
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: QuickCaptureView().environment(self).environment(session).environment(library))
            quick = panel
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            quick?.setFrameOrigin(.init(x: screen.visibleFrame.midX - 210, y: screen.visibleFrame.midY - 160))
        }
        quick?.makeKeyAndOrderFront(nil)
        Task {
            guard let api = session.client(), let account = session.userID else { return }
            await library.refreshSpaces(api, account: account)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLibrary() {
        CloseAndHide.restoreDockIcon()
        if let openLibrary {
            openLibrary()
        } else {
            let window = NSApp.windows.first { $0.identifier?.rawValue == "library" } ?? CloseAndHide.libraryWindow
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-orders the existing pin after an activation-policy change. Does not alter pin layout or gestures.
    func showPinIfEnabled() {
        pin?.update(enabled: pinEnabled)
    }

    func paste(quietly: Bool = false) {
        guard canStart() else { return }
        quiet = quietly
        let board = NSPasteboard.general
        let account = session.userID
        do {
            if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
                guard files.count == 1 else { throw QueepError.server("Cole uma imagem por vez.") }
                receive([NSItemProvider(contentsOf: files[0])].compactMap { $0 }, quietly: quietly, source: "paste")
            } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
                busy = true
                if !quiet { show() }
                Task {
                    do {
                        let image = try await Task.detached { try ImportedImage.prepare(data: data) }.value
                        busy = false
                        await send(IncomingReference(text: "", url: nil, image: image.data), account: account, source: "paste")
                    } catch { fail(error) }
                }
            } else if let text = board.string(forType: .URL) ?? board.string(forType: .string) {
                let incoming = try IncomingReference.text(text)
                busy = true
                Task { await send(incoming, account: account, source: "paste") }
            } else { throw QueepError.server("Copie uma imagem, um link ou um texto primeiro.") }
        } catch { fail(error) }
    }

    func receive(_ providers: [NSItemProvider], quietly: Bool = false, source: String = "drag") {
        guard canStart() else { return }
        quiet = quietly
        let account = session.userID
        busy = true; error = nil; message = "Preparando…"
        if !quiet { show() }
        Task {
            do {
                guard let client = session.client() else { throw QueepError.unauthorized }
                let incoming = try await IncomingLoader.load(providers, authorizeMedia: {
                    try await client.requireMediaAccess()
                })
                busy = false
                await send(incoming, account: account, source: source)
            } catch { fail(error) }
        }
    }

    func saveDraft() {
        guard canStart() else { return }
        do {
            let incoming = try IncomingReference.text(draft)
            let account = session.userID
            busy = true
            Task { await send(incoming, account: account, source: "shortcut") }
        } catch { fail(error) }
    }

    func retry() {
        guard let pending, !busy else { return }
        let account = owner
        let source = pendingSource
        busy = true
        Task { await send(pending, account: account, source: source) }
    }

    func discard() { guard !busy else { return }; pending = nil; owner = nil; message = nil; error = nil; quiet = false }

    func captureScreen(quietly: Bool = false) {
        guard canStart() else { return }
        quiet = quietly
        let account = session.userID
        quick?.orderOut(nil)
        screenshot.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let bytes):
                busy = true
                Task { await self.send(IncomingReference(title: "Captura de tela", text: "", url: nil, image: bytes), account: account, source: "shortcut") }
            case .failure(let failure): fail(failure)
            }
        }
    }

    private func canStart() -> Bool {
        guard session.userID != nil else { error = "Entre na sua conta pela biblioteca do Queep."; show(); return false }
        guard !busy, pending == nil, !screenshot.active else {
            error = "Conclua o envio atual ou descarte-o antes de adicionar outro."; show(); return false
        }
        error = nil; message = nil
        return true
    }

    private func send(_ incoming: IncomingReference, account: String?, source: String) async {
        guard let account, session.userID == account, let api = session.client() else {
            fail(QueepError.server("A conta mudou. Repita a captura na conta desejada.")); return
        }
        var incoming = incoming
        if pending == nil { incoming.spaceIDs = quiet ? [] : captureSpaceID.map { [$0] } ?? [] }
        pending = incoming; pendingSource = source; owner = account; busy = true; error = nil; message = "Salvando…"
        if !quiet { show() }
        do {
            let saved = try await incoming.save(using: api)
            guard session.userID == account else { pending = nil; busy = false; quiet = false; return }
            ProductAnalytics.captureSaved(kind: saved.kind, url: saved.url, source: source)
            pending = nil; owner = nil; busy = false; quiet = false; draft = ""; message = Self.savedMessage
            captureSpaceID = nil
            library.reset(for: account)
            await library.refresh(api, account: account, force: true)
        } catch { fail(error) }
    }

    private func fail(_ failure: Error) { busy = false; quiet = false; message = nil; error = failure.localizedDescription; show() }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

private struct QuickCaptureView: View {
    @Environment(MacCapture.self) private var capture
    @Environment(Session.self) private var session
    var body: some View {
        @Bindable var capture = capture
        VStack(alignment: .leading, spacing: 12) {
            Text("Guarde o que você quer lembrar").font(.headline)
            CaptureSpaceChoice(selection: $capture.captureSpaceID)
                .disabled(capture.busy || capture.pending != nil)
            TextEditor(text: $capture.draft).frame(height: 100)
                .accessibilityLabel("Nota ou link").accessibilityIdentifier("quick.text")
                .disabled(capture.busy || capture.pending != nil)
            HStack {
                Button("Colar e salvar") { capture.paste() }.accessibilityIdentifier("quick.paste")
                Button("Capturar tela") { capture.captureScreen() }.accessibilityIdentifier("quick.screenshot")
                Spacer()
                Button("Salvar") { capture.saveDraft() }.keyboardShortcut(.return, modifiers: .command)
                    .disabled(capture.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("quick.save")
            }.disabled(capture.busy || capture.pending != nil || session.userID == nil)
            if capture.busy { ProgressView("Salvando…").controlSize(.small) }
            if let message = capture.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            if let error = capture.error { Text(error).font(.callout).foregroundStyle(.red) }
            if capture.pending != nil && !capture.busy {
                HStack {
                    Button("Tentar novamente") { capture.retry() }
                    Button("Descartar envio") { capture.discard() }
                }
            }
            Text("⌘⇧Espaço abre esta janela · ⌘⇧7 captura a tela · Esc fecha")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(18).frame(width: 420).subscriptionGate()
    }
}
