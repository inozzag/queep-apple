import AppKit
import Observation
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MacCapture {
    static let shared = MacCapture()
    let session = Session()
    let library = LibraryStore()
    var draft = ""
    var busy = false
    var message: String?
    var error: String?
    var pending: IncomingReference?
    var shortcutIssues: [String] = []
    var shelfEnabled = UserDefaults.standard.object(forKey: "queep.shelf.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shelfEnabled, forKey: "queep.shelf.enabled"); updateShelf() }
    }
    private var owner: String?
    private var quick: NSPanel?
    private var shelf: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private let screenshot = ScreenCapture()

    init() {
        session.onAccountChange = { [weak self] in
            guard let self else { return }
            draft = ""; pending = nil; owner = nil; error = nil; message = nil
            screenshot.cancel()
            library.reset(for: session.userID)
        }
    }

    func install() {
        updateShelf()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateShelf() } }
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
            panel.contentView = NSHostingView(rootView: QuickCaptureView().environment(self).environment(session))
            quick = panel
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            quick?.setFrameOrigin(.init(x: screen.visibleFrame.midX - 210, y: screen.visibleFrame.midY - 160))
        }
        quick?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateShelf() {
        shelf?.orderOut(nil)
        guard shelfEnabled, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        if shelf == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: CaptureShelf().environment(self))
            shelf = panel
        }
        let topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        shelf?.setFrame(.init(x: screen.frame.midX - 92, y: screen.frame.maxY - topInset - 34,
                             width: 184, height: 30), display: true)
        shelf?.orderFrontRegardless()
    }

    func paste() {
        guard canStart() else { return }
        let board = NSPasteboard.general
        let account = session.userID
        do {
            if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
                guard files.count == 1 else { throw QueepError.server("Cole uma imagem por vez.") }
                receive([NSItemProvider(contentsOf: files[0])].compactMap { $0 })
            } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
                busy = true; show()
                Task {
                    do {
                        let image = try await Task.detached { try ImportedImage.prepare(data: data) }.value
                        busy = false
                        await send(IncomingReference(text: "", url: nil, image: image.data), account: account)
                    } catch { fail(error) }
                }
            } else if let text = board.string(forType: .URL) ?? board.string(forType: .string) {
                let incoming = try IncomingReference.text(text)
                busy = true
                Task { await send(incoming, account: account) }
            } else { throw QueepError.server("Copie uma imagem, um link ou um texto primeiro.") }
        } catch { fail(error) }
    }

    func receive(_ providers: [NSItemProvider]) {
        guard canStart() else { return }
        let account = session.userID
        busy = true; error = nil; message = "Preparando…"; show()
        Task {
            do {
                let incoming = try await IncomingLoader.load(providers)
                busy = false
                await send(incoming, account: account)
            } catch { fail(error) }
        }
    }

    func saveDraft() {
        guard canStart() else { return }
        do {
            let incoming = try IncomingReference.text(draft)
            let account = session.userID
            busy = true
            Task { await send(incoming, account: account) }
        } catch { fail(error) }
    }

    func retry() {
        guard let pending, !busy else { return }
        let account = owner
        busy = true
        Task { await send(pending, account: account) }
    }

    func discard() { guard !busy else { return }; pending = nil; owner = nil; message = nil; error = nil }

    func captureScreen() {
        guard canStart() else { return }
        let account = session.userID
        quick?.orderOut(nil)
        screenshot.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let bytes):
                busy = true
                Task { await self.send(IncomingReference(title: "Captura de tela", text: "", url: nil, image: bytes), account: account) }
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

    private func send(_ incoming: IncomingReference, account: String?) async {
        guard let account, session.userID == account, let api = session.client() else {
            fail(QueepError.server("A conta mudou. Repita a captura na conta desejada.")); return
        }
        pending = incoming; owner = account; busy = true; error = nil; message = "Salvando…"; show()
        do {
            _ = try await incoming.save(using: api)
            guard session.userID == account else { pending = nil; busy = false; return }
            pending = nil; owner = nil; busy = false; draft = ""; message = "Salvo · análise em segundo plano"
            library.reset(for: account)
            await library.refresh(api, account: account)
        } catch { fail(error) }
    }

    private func fail(_ failure: Error) { busy = false; message = nil; error = failure.localizedDescription; show() }
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
        }.padding(18).frame(width: 420)
    }
}

private struct CaptureShelf: View {
    @Environment(MacCapture.self) private var capture
    @State private var targeted = false
    var body: some View {
        Button { capture.show() } label: {
            Label(targeted ? "Solte para salvar" : "Queep · solte aqui", systemImage: "tray.and.arrow.down")
                .font(.caption).padding(.horizontal, 14).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(targeted ? Color.accentColor : .secondary.opacity(0.25)))
        }.buttonStyle(.plain)
        .accessibilityLabel("Captura rápida do Queep")
        .accessibilityHint("Clique para adicionar ou solte uma imagem, um link ou texto")
        .onDrop(of: [UTType.url, .image, .plainText, .movie, .audio], isTargeted: $targeted) { providers in
            capture.receive(providers); return true
        }
    }
}
