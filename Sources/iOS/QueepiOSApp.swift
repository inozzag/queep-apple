import SwiftUI

@main
struct QueepiOSApp: App {
    @State private var session = Session()
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView().environment(session).environment(library)
        }
    }
}
