import Foundation
import QueepCore
import Sentry
import Security

/// Crash and unexpected API failure reporting for Queep iPhone, Mac, and the share extension.
///
/// App Store privacy nutrition label, to declare at publication (not submitted in this change):
/// Diagnostics — Crash Data, linked to the Firebase UID, used for app functionality.
/// Collected from Queep iPhone, Queep Mac, and the share extension.
/// Not collected: note text, saved URLs, search queries, file names, tokens, email, or passwords.
/// The Sentry Cocoa SDK ships its privacy manifest inside the linked xcframework.
@MainActor
enum CrashReporting {
    private static var started = false

    static var platform: String {
        #if QUEEP_SHARE
        "share"
        #elseif os(iOS)
        "ios"
        #else
        "mac"
        #endif
    }

    /// No-ops without a DSN, and never in local Debug (`127.0.0.1` / emulator).
    static func start() {
        guard !started else { return }
        started = true
        #if DEBUG && QUEEP_SHARE
        let args = ProcessInfo.processInfo.arguments.joined(separator: " ")
        shareDebugNote("args=\(args)")
        #endif
        guard let environment = environment, let dsn = dsn() else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.debug = false
            options.sendDefaultPii = false
            options.sampleRate = 1
            options.enableCrashHandler = true
            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
            #if os(iOS)
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            #endif
            options.enableCaptureFailedRequests = false
            options.enableNetworkBreadcrumbs = false
            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0
            options.enableLogs = false
            options.enableMetrics = false
            options.configureProfiling = {
                $0.sessionSampleRate = 0
            }
            #if os(iOS) && !QUEEP_SHARE
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            #endif
            options.beforeSend = { event in
                scrub(event)
            }
            options.beforeBreadcrumb = { crumb in
                sanitize(crumb)
            }
        }
        SentrySDK.configureScope { scope in
            scope.setTag(value: platform, key: "platform")
        }
        APIDiagnostics.record = { failure in
            capture(failure)
        }
        SessionDiagnostics.onUserChange = { syncUser($0) }
        syncUser(SessionDiagnostics.userID)
        #if DEBUG && QUEEP_SHARE
        let asked = ProcessInfo.processInfo.arguments.contains("--sentry-test-share") || consumeShareCrashFlag()
        if asked {
            let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("queep-sentry-share-crashed")
            if FileManager.default.fileExists(atPath: marker.path) {
                try? FileManager.default.removeItem(at: marker)
                shareDebugNote("flush")
            } else {
                try? Data("1".utf8).write(to: marker, options: .atomic)
                shareDebugNote("will-crash")
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
                    SentrySDK.crash()
                }
            }
        } else {
            shareDebugNote("no-crash")
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--sentry-test-crash"), platform == "share" {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
                SentrySDK.crash()
            }
        }
        #endif
    }

    static func syncUser(_ uid: String?) {
        guard SentrySDK.isEnabled else { return }
        guard let uid, !uid.isEmpty else {
            SentrySDK.setUser(nil)
            return
        }
        let user = User()
        user.userId = uid
        SentrySDK.setUser(user)
        scheduleTestCrashIfNeeded(uid)
    }

    #if DEBUG && QUEEP_SHARE
    nonisolated static func shareDebugNote(_ message: String) {
        NSLog("queep-share %@", message)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("queep-share-ext.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data("\(message)\n".utf8))
            try? handle.close()
        } else {
            try? Data("\(message)\n".utf8).write(to: url)
        }
    }

    /// One crash, then the next activation only starts Sentry so the report can leave.
    /// The shared payload is not rendered and is not added to the event.
    static func consumeShareTestCrash(_ context: NSExtensionContext?) -> Bool {
        let marked = (context?.inputItems ?? []).contains { item in
            guard let item = item as? NSExtensionItem else { return false }
            let flag = item.userInfo?["queep.sentry-test-crash"]
            return (flag as? Bool) == true || (flag as? NSNumber)?.boolValue == true
        }
        guard marked else {
            scheduleSharePayloadCrash(context)
            return false
        }
        let marker = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queep-sentry-share-crashed")
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: marker.path) {
            try? FileManager.default.removeItem(at: marker)
            return true
        }
        try? Data("1".utf8).write(to: marker, options: .atomic)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            SentrySDK.crash()
        }
        return true
    }

    /// A share sheet does not receive the host's launch arguments. The test page URL carries
    /// the marker; the payload is not rendered into the event.
    private static func scheduleSharePayloadCrash(_ context: NSExtensionContext?) {
        let items = (context?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        let providers = items.flatMap { $0.attachments ?? [] }
        let inline = items.compactMap { $0.attributedContentText?.string }.joined(separator: "\n")
        if inline.contains("queep-sentry-test-crash") {
            armShareCrashOnce()
            return
        }
        for provider in providers {
            for type in ["public.url", "public.plain-text", "public.text"] where provider.hasItemConformingToTypeIdentifier(type) {
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    let text = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
                    guard text.contains("queep-sentry-test-crash") else { return }
                    DispatchQueue.main.async { armShareCrashOnce() }
                }
            }
        }
    }

    private static func armShareCrashOnce() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let marker = base.appendingPathComponent("queep-sentry-share-crashed")
        if FileManager.default.fileExists(atPath: marker.path) {
            try? FileManager.default.removeItem(at: marker)
            shareDebugNote("flush")
            return
        }
        try? Data("1".utf8).write(to: marker, options: .atomic)
        shareDebugNote("will-crash")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            SentrySDK.crash()
        }
    }
    #endif

    #if DEBUG
    /// The host app sets this in the shared keychain. The extension deletes it and crashes once,
    /// so the next activation can send the report. The shared payload is not part of the flag.
    nonisolated static func setShareCrashFlag() -> OSStatus {
        guard var query = shareCrashQuery() else { return errSecParam }
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data("1".utf8)
        return SecItemAdd(query as CFDictionary, nil)
    }

    nonisolated static func consumeShareCrashFlag() -> Bool {
        guard let query = shareCrashQuery() else { return false }
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    nonisolated private static func shareCrashQuery() -> [String: Any]? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "QueepAuthGroup") as? String,
              !group.isEmpty else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "queep.sentry.share",
            kSecAttrAccount as String: "crash",
            kSecAttrAccessGroup as String: group
        ]
    }

    private static var testCrashScheduled = false

    /// CloudDevelopment can ask for one crash after the Firebase UID is attached.
    /// A normal launch never passes the argument.
    private static func scheduleTestCrashIfNeeded(_ uid: String?) {
        guard !testCrashScheduled,
              let uid, !uid.isEmpty,
              ProcessInfo.processInfo.arguments.contains("--sentry-test-crash") else { return }
        testCrashScheduled = true
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            SentrySDK.crash()
        }
    }
    #else
    private static func scheduleTestCrashIfNeeded(_ uid: String?) {}
    #endif

    nonisolated private static func capture(_ failure: APIDiagnostics.Failure) {
        guard SentrySDK.isEnabled else { return }
        let status = failure.status.map(String.init) ?? "transport"
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "API \(failure.method) \(failure.path) failed (\(status))")
        var tags = ["api.method": failure.method, "api.status": status]
        if let code = failure.transportCode {
            tags["api.transport_code"] = String(code)
        }
        event.tags = tags
        SentrySDK.capture(event: event)
    }

    nonisolated private static func scrub(_ event: Event) -> Event? {
        event.request = nil
        event.user?.email = nil
        event.user?.username = nil
        event.user?.ipAddress = nil
        if let data = event.user?.data {
            event.user?.data = DiagnosticScrubber.scrub(data)
        }
        event.extra = DiagnosticScrubber.scrub(event.extra ?? [:])
        if var context = event.context {
            for (key, value) in context {
                context[key] = DiagnosticScrubber.scrub(value)
            }
            event.context = context
        }
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: DiagnosticScrubber.redact(formatted))
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap(sanitize)
        return event
    }

    nonisolated private static func sanitize(_ crumb: Breadcrumb) -> Breadcrumb? {
        if crumb.category == "http" || crumb.type == "http" { return nil }
        if let data = crumb.data {
            crumb.data = DiagnosticScrubber.scrub(data)
        }
        if let message = crumb.message {
            crumb.message = DiagnosticScrubber.redact(message)
        }
        return crumb
    }

    private static var environment: String? {
        #if DEBUG && QUEEP_CLOUD
        "development"
        #elseif QUEEP_CLOUD
        "testflight"
        #else
        nil
        #endif
    }

    private static func dsn() -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "QueepSentryDSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.hasPrefix("https://"), value.contains("@"),
              !value.contains("$("), !value.contains(" ") else { return nil }
        return value
    }
}
