import GoogleSignIn
import SwiftUI

@main
struct QueepiOSApp: App {
    @State private var session = Session()
    @State private var library = LibraryStore()

    init() { ProductAnalytics.start() }

    var body: some Scene {
        WindowGroup {
            RootView().environment(session).environment(library)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
