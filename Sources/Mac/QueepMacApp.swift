import SwiftUI
import ServiceManagement

@main
struct QueepMacApp: App {
    @NSApplicationDelegateAdaptor(MacDelegate.self) private var delegate
    @State private var session = Session()
    @State private var library = LibraryStore()

    var body: some Scene {
        Window("Queep", id: "library") {
            MacRootView().environment(session).environment(library)
                .frame(minWidth: 660, minHeight: 500)
        }.defaultSize(width: 1040, height: 720)
        MenuBarExtra("Queep", systemImage: "bookmark.fill") {
            QueepMenu().environment(session).environment(library)
        }
    }
}

private struct MacRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(LibraryStore.self) private var library
    @Environment(Session.self) private var session
    var body: some View {
        RootView().onReceive(NotificationCenter.default.publisher(for: .queepQuickCapture)) { _ in
            openWindow(id: "library")
            NSApplication.shared.activate(ignoringOtherApps: true)
            if session.userID != nil { library.presentation = .capture(UUID()) }
        }
    }
}

private struct QueepMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(LibraryStore.self) private var library
    @Environment(Session.self) private var session
    @State private var loginError: String?

    var body: some View {
        Button("Abrir biblioteca") { showLibrary() }
        Button("Adicionar referência") { showLibrary(); library.presentation = .capture(UUID()) }.disabled(session.userID == nil)
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
