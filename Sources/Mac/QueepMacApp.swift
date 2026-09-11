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
        }.defaultSize(width: 1040, height: 720)
        MenuBarExtra("Queep", systemImage: "bookmark.fill") {
            QueepMenu().environment(capture.session).environment(capture.library).environment(capture)
        }
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
        Toggle("Área de envio no topo", isOn: Binding(get: { capture.shelfEnabled }, set: { capture.shelfEnabled = $0 }))
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
