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
            } else if let message = session.accountLoadError {
                AccountLoadFailureView(message: message)
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
            await ProductAnalytics.syncIdentity(session)
            await ProductAnalytics.deliverSharedCaptures(session)
            await library.refresh(api, account: uid)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard phase == .active else { continue }
                // Account closure must also dismiss details and capture sheets on other devices.
                await session.handleUnauthorized(uid)
                await ProductAnalytics.deliverSharedCaptures(session)
                // Keep an open detail, and any queued or processing card, current. Idle libraries wait for a manual refresh.
                if library.shouldKeepRefreshing {
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

private struct AccountLoadFailureView: View {
    @Environment(Session.self) private var session
    let message: String
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 20) {
            QueepLogo(size: 72)
            Text("Não foi possível carregar sua conta")
                .font(.title2.bold())
                .foregroundStyle(Theme.homeInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("account.load.title")
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.homePreview)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account.load.error")
            Button {
                Task {
                    retrying = true
                    defer { retrying = false }
                    await session.retryAccountLoad()
                }
            } label: {
                HStack(spacing: 8) {
                    if retrying { ProgressView().controlSize(.small).tint(.white) }
                    Text("Tentar novamente")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.homeChrome)
                .background(Theme.homeAccent, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(retrying)
            .accessibilityIdentifier("account.load.retry")
            Button("Sair da conta") { try? session.signOut() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.homePreview)
                .buttonStyle(.plain)
                .disabled(retrying)
                .accessibilityIdentifier("account.load.signout")
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color.white)
        #else
        .background(Color.canvas)
        #endif
    }
}
