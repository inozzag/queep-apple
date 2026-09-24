import ObjectiveC
import GoogleSignIn
import SwiftUI

@main
struct QueepiOSApp: App {
    @State private var session = Session()
    @State private var library = LibraryStore()

    init() {
        CrashReporting.start()
        ProductAnalytics.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(session).environment(library)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { await ShareCrashProbe.runIfRequested() }
        }
    }
}

/// DEBUG-only. Loads the embedded share extension through the system so a crash is
/// attributed to that process. A normal launch never passes `--sentry-test-share`.
enum ShareCrashProbe {
    static func runIfRequested() async {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--sentry-test-share") else { return }
        let identifier = (Bundle.main.bundleIdentifier ?? "") + ".share"
        guard let cls = NSClassFromString("NSExtension") else {
            note("NSExtension missing")
            return
        }
        let lookupSel = NSSelectorFromString("extensionWithIdentifier:error:")
        typealias Lookup = @convention(c) (AnyObject, Selector, NSString, UnsafeMutablePointer<NSError?>?) -> NSObject?
        let lookup = unsafeBitCast(
            class_getMethodImplementation(object_getClass(cls), lookupSel),
            to: Lookup.self)
        var error: NSError?
        guard let ext = lookup(cls, lookupSel, identifier as NSString, &error) else {
            note("missing \(identifier) \(error?.localizedDescription ?? "")")
            return
        }
        note("found \(identifier)")
        let status = CrashReporting.setShareCrashFlag()
        note("flag \(status)")
        await request(ext)
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        await request(ext)
        note("flush wait")
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        note("done")
        #endif
    }

    #if DEBUG
    private static func note(_ message: String) {
        print("share-probe: \(message)")
        fflush(stdout)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("share-probe.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data("\(message)\n".utf8))
            try? handle.close()
        } else {
            try? Data("\(message)\n".utf8).write(to: url)
        }
    }

    private static func request(_ ext: NSObject) async {
        let item = NSExtensionItem()
        item.userInfo = ["queep.sentry-test-crash": true]
        let secret = "https://segredo.example/nota-que-nao-pode-ir-ao-sentry"
        item.attachments = [
            NSItemProvider(item: URL(string: secret)! as NSURL, typeIdentifier: "public.url"),
            NSItemProvider(item: "Frase secreta share gaz122 que nao pode ir ao sentry" as NSString,
                           typeIdentifier: "public.plain-text")
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let sel = NSSelectorFromString("beginExtensionRequestWithInputItems:completion:")
            typealias Begin = @convention(c) (NSObject, Selector, NSArray, @convention(block) (NSUUID?) -> Void) -> Void
            let extClass: AnyClass = object_getClass(ext) ?? NSObject.self
            let begin = unsafeBitCast(class_getMethodImplementation(extClass, sel), to: Begin.self)
            let done: @convention(block) (NSUUID?) -> Void = { id in
                note("request \(id?.uuidString ?? "nil")")
                cont.resume()
            }
            begin(ext, sel, [item], done)
        }
    }
    #endif
}
