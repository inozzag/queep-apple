import SwiftUI
import QueepCore

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let error = session.configurationError {
                ContentUnavailableView("Configuração pendente", systemImage: "icloud.slash",
                                       description: Text(error))
            } else if session.preparing {
                ProgressView("Abrindo sua biblioteca…")
            } else if let state = session.accountState, !state.isActive {
                AccountRecoveryView(state: state)
            } else if session.userID != nil {
                LibraryView()
            } else { SignInView() }
        }
        // Queep uses a deliberately light, paper-like canvas on every platform.
        // Never inherit the system appearance: dark mode changes contrast, icons and surfaces.
        .preferredColorScheme(.light)
        .onOpenURL { url in
            if url.scheme == Bundle.main.object(forInfoDictionaryKey: "QueepURLScheme") as? String,
               url.host == "subscription" {
                session.planRequirement = .media(for: .free)
            }
        }
        .task(id: SyncKey(userID: session.userID, owner: session.accountOwner, active: phase == .active)) {
            library.reset(for: session.userID)
            if session.userID == nil { await SubscriptionStore.shared.clearSession(session) }
            guard phase == .active else { return }
            if session.userID == nil, let owner = session.accountOwner {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    await session.handleUnauthorized(owner)
                }
                return
            }
            guard let uid = session.userID, let api = session.client() else { return }
            await library.refresh(api, account: uid)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard phase == .active else { continue }
                // Account closure must also dismiss details and capture sheets on other devices.
                await session.handleUnauthorized(uid)
                // Keep polling while a post is open so carousel photos appear after analysis.
                if library.items.count <= 40 {
                    await library.refresh(api, account: uid)
                }
            }
        }
    }

    private struct SyncKey: Equatable {
        let userID: String?
        let owner: String?
        let active: Bool
    }
}
