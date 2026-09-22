import AppKit
import SwiftUI
import ServiceManagement

@main
struct QueepMacApp: App {
    @NSApplicationDelegateAdaptor(MacDelegate.self) private var delegate
    @State private var capture = MacCapture.shared

    var body: some Scene {
        Window("Queep", id: "library") {
            RootView().environment(capture.session).environment(capture.library)
                .frame(minWidth: 1080, minHeight: 640)
                .background(LibraryOpener(capture: capture))
                .modifier(HideLibraryWindowTitle())
        }.defaultSize(width: 1315, height: 848)
        MenuBarExtra {
            QueepMenu().environment(capture.session).environment(capture.library).environment(capture)
        } label: {
            Image(nsImage: MenuBarLogo.image)
                .accessibilityLabel("Queep")
        }
    }
}

/// 18pt template; MenuBarExtra uses the image's native size and HomeLogo is hundreds of points.
private enum MenuBarLogo {
    static let image: NSImage = {
        let source = NSImage(named: "MenuBarLogo") ?? NSImage(named: "HomeLogo") ?? NSImage()
        let points = NSSize(width: 18, height: 18)
        let pixels = 36
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return source }
        rep.size = points
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: points), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let icon = NSImage(size: points)
        icon.addRepresentation(rep)
        icon.isTemplate = true
        return icon
    }()
}

/// Keeps the glass titlebar and traffic lights; hides the redundant window title next to them.
private struct HideLibraryWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        titleHidden(content)
            .background(WindowTitleHider())
    }

    @ViewBuilder
    private func titleHidden(_ content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleHidingView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitleHidingView)?.hideTitle()
    }
}

private final class TitleHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideTitle()
    }

    func hideTitle() {
        window?.titleVisibility = .hidden
    }
}

/// Hands the scene's window opener to the capture controller so the island can reopen the library.
private struct LibraryOpener: View {
    @Environment(\.openWindow) private var openWindow
    let capture: MacCapture
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { capture.openLibrary = { openWindow(id: "library") } }
    }
}

private struct QueepMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(LibraryStore.self) private var library
    @Environment(Session.self) private var session
    @Environment(MacCapture.self) private var capture
    @State private var loginError: String?

    var body: some View {
        Button("Abrir biblioteca") { showLibrary() }
        Button("Captura rápida · ⌘⇧Espaço") { capture.show() }
        Button("Colar e salvar") { capture.paste() }.disabled(session.userID == nil)
        Button("Capturar tela · ⌘⇧7") { capture.captureScreen() }.disabled(session.userID == nil)
        Toggle("Ilha de captura no topo da tela", isOn: Binding(get: { capture.islandEnabled }, set: { capture.islandEnabled = $0 }))
        ForEach(capture.shortcutIssues, id: \.self) { Text($0) }
        Divider()
        Toggle("Iniciar com o Mac", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { value in
                do {
                    if value { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch { loginError = "Não foi possível alterar o início automático." }
            }
        ))
        if let loginError { Text(loginError) }
        Divider()
        Button("Encerrar Queep") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }

    private func showLibrary() {
        openWindow(id: "library")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
