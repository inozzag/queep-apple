import SwiftUI
import ServiceManagement

@main
struct QueepMacApp: App {
    @NSApplicationDelegateAdaptor(MacDelegate.self) private var delegate
    @State private var capture = MacCapture.shared

    var body: some Scene {
        Window("Queep", id: "library") {
            RootView().environment(capture.session).environment(capture.library)
                .frame(minWidth: 660, minHeight: 500)
                .background(LibraryOpener(capture: capture))
        }.defaultSize(width: 1040, height: 720)
        MenuBarExtra("Queep", systemImage: "bookmark.fill") {
            QueepMenu().environment(capture.session).environment(capture.library).environment(capture)
        }
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
