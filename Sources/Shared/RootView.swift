import SwiftUI
import QueepCore

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var phase
    @State private var activity = LibraryActivity()

    #if DEBUG
    @State private var previewPaywall = EntryPreview.paywall
    #endif

    private var loading: Bool {
        #if DEBUG
        if EntryPreview.loading { return true }
        #endif
        return session.preparing
    }

    /// Opening the session and signing in are one screen, so the ticker keeps moving between them.
    private var showsEntry: Bool {
        if loading { return true }
        if let state = session.accountState, !state.isActive { return false }
        return session.userID == nil
    }

    var body: some View {
        ZStack {
            if let error = session.configurationError {
                ContentUnavailableView("Configuração pendente", systemImage: "icloud.slash",
                                       description: Text(error))
            } else if showsEntry {
                EntryView(loading: loading)
                    .transition(.opacity)
            } else if let state = session.accountState, !state.isActive {
                AccountRecoveryView(state: state)
            } else {
                LibraryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showsEntry)
        #if DEBUG
        .journeyPaywall(Binding(
            get: {
                previewPaywall
                    ? PaywallContext(reason: EntryPreview.resource == nil ? "preview" : "plan_limit",
                                     resource: EntryPreview.resource)
                    : nil
            },
            set: { previewPaywall = $0 != nil }))
        #endif
        // Queep uses a deliberately light, paper-like canvas on every platform.
        // Never inherit the system appearance: dark mode changes contrast, icons and surfaces.
        .preferredColorScheme(.light)
        .onOpenURL { url in
            if url.scheme == Bundle.main.object(forInfoDictionaryKey: "QueepURLScheme") as? String,
               url.host == "subscription" {
                session.planRequirement = .media(for: .free)
            }
        }
        .onChange(of: phase, initial: true) { _, phase in
            activity.active = phase == .active
        }
        .task(id: AccountKey(userID: session.userID, owner: session.accountOwner)) {
            library.reset(for: session.userID)
            if session.userID == nil { await SubscriptionStore.shared.clearSession(session) }
            if session.userID == nil, let owner = session.accountOwner {
                while !Task.isCancelled {
                    guard activity.active else {
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    await session.handleUnauthorized(owner)
                }
                return
            }
            guard let uid = session.userID, let api = session.client() else { return }
            while !activity.active && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            await ProductAnalytics.syncIdentity(session)
            await ProductAnalytics.deliverSharedCaptures(session)
            // Cache is already on screen. This hits the network only when that cache is missing or stale.
            await library.refresh(api, account: uid)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard activity.active else { continue }
                await session.handleUnauthorized(uid)
                await ProductAnalytics.deliverSharedCaptures(session)
                if library.hasPendingAnalysis {
                    await library.refresh(api, account: uid, force: true)
                } else {
                    await library.refresh(api, account: uid)
                }
            }
        }
    }

    private struct AccountKey: Equatable {
        let userID: String?
        let owner: String?
    }
}

#if DEBUG
/// Design review without the emulators. A normal launch never passes these arguments.
/// `--preview-loading` holds the opening screen; `--preview-paywall-sample` shows the Max sheet
/// with sample prices, and `--preview-paywall-notice` opens it as a spent capture quota would.
private enum EntryPreview {
    static let loading = ProcessInfo.processInfo.arguments.contains("--preview-loading")
    static let paywall = ProcessInfo.processInfo.arguments.contains("--preview-paywall-sample")
    static let resource = ProcessInfo.processInfo.arguments.contains("--preview-paywall-notice")
        ? "operations" : nil
}
#endif

/// Shared with the library task so a focus change does not cancel the fetch and restart the spinner.
private final class LibraryActivity {
    var active = false
}
