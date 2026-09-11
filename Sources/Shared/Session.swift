import FirebaseAuth
import FirebaseCore
import Observation
import QueepCore
import SwiftUI

@MainActor @Observable
final class Session {
    var userID: String? {
        didSet { if oldValue != userID { onAccountChange?() } }
    }
    var onAccountChange: (() -> Void)?
    var configurationError: String?
    var isLocal = false
    var apiURL: URL?
    var preparing = true
    var accountNotice: String?
    var accountState: AccountStatus?
    var accountOwner: String?
    var deletingAccount = false
    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        #if DEBUG && !QUEEP_CLOUD
        do {
            let options = FirebaseOptions(googleAppID: "1:123456789:ios:0123456789abcdef01234567",
                                          gcmSenderID: "123456789")
            options.projectID = "demo-queep"
            options.apiKey = "local-emulator-key"
            if FirebaseApp.app() == nil {
                FirebaseApp.configure(options: options)
                Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                try? Auth.auth().signOut()
            }
            apiURL = URL(string: "http://127.0.0.1:8000")
            isLocal = true
        }
        #else
        configureCloud()
        #endif
        guard configurationError == nil else { preparing = false; return }
        Task { await finishSetup() }
    }

    private func finishSetup() async {
        defer { preparing = false }
        #if os(iOS)
        do {
            if let group = Bundle.main.object(forInfoDictionaryKey: "QueepAuthGroup") as? String {
                let auth = Auth.auth()
                let previous = auth.currentUser
                let wasPrivate = auth.userAccessGroup == nil
                try auth.useUserAccessGroup(group)
                // Move the already signed-in user once; never revive a shared session after logout.
                if wasPrivate, auth.currentUser == nil, let previous {
                    try await auth.updateCurrentUser(previous)
                }
            }
        } catch {
            configurationError = "Não foi possível preparar o acesso compartilhado. Abra o Queep novamente."
            return
        }
        #endif
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self, Auth.auth().currentUser?.uid == user?.uid else { return }
                if let user { try? await self.refreshAccount(owner: user.uid) }
                else { self.clearAccountState() }
            }
        }
        if let user = Auth.auth().currentUser {
            do { try await refreshAccount(owner: user.uid) }
            catch { accountNotice = "Conecte-se à internet e entre novamente para verificar sua conta." }
        }
        #if DEBUG
        // Test fixtures still authenticate against Firebase; never enabled for cloud builds.
        if isLocal, ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let email = ProcessInfo.processInfo.environment["QUEEP_TEST_EMAIL"],
           let password = ProcessInfo.processInfo.environment["QUEEP_TEST_PASSWORD"] {
            Task { try await signIn(email: email, password: password, create: false) }
        }
        #endif
    }

    private func configureCloud() {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "QueepAPIURL") as? String,
              let url = URL(string: urlString), url.scheme == "https", url.host != nil,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              let expectedProject = Bundle.main.object(forInfoDictionaryKey: "QueepFirebaseProjectID") as? String,
              options.projectID == expectedProject,
              options.bundleID == Bundle.main.bundleIdentifier else {
            configurationError = "Esta versão ainda não está configurada para conexão com a nuvem."
            return
        }
        // The system can reuse a Share Extension process for another presentation.
        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        apiURL = url
    }

    func signIn(email: String, password: String, create: Bool) async throws {
        if create {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
        } else {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        }
        if let user = Auth.auth().currentUser { try await refreshAccount(owner: user.uid) }
        accountNotice = nil
    }

    func signOut() throws {
        try Auth.auth().signOut()
        clearAccountState()
    }

    private func clearAccountState() {
        userID = nil; accountState = nil; accountOwner = nil
    }

    func apply(_ state: AccountStatus, owner: String) {
        guard Auth.auth().currentUser?.uid == owner else { return }
        if accountOwner == owner, let previous = accountState, previous.version > state.version { return }
        accountOwner = owner; accountState = state
        userID = state.isActive ? owner : nil
    }

    func refreshAccount(owner: String) async throws {
        guard let apiURL else { throw QueepError.unauthorized }
        let api = APIClient(baseURL: apiURL) { [weak self] in
            guard let self else { throw QueepError.unauthorized }
            return try await self.token(for: owner)
        }
        let state = try await api.accountStatus()
        apply(state, owner: owner)
    }

    func handleUnauthorized(_ owner: String) async {
        do { try await refreshAccount(owner: owner) }
        catch { invalidate(owner) }
    }

    func invalidate(_ owner: String) {
        guard userID == owner || accountOwner == owner else { return }
        if let current = Auth.auth().currentUser, current.uid != owner {
            return
        }
        try? Auth.auth().signOut()
        clearAccountState()
        accountNotice = "Sua sessão foi encerrada. Entre novamente se sua conta ainda estiver ativa."
    }

    func changeAccountDeletion(password: String, owner: String, version: Int,
                               operationID: UUID, immediate: Bool = false, cancel: Bool = false) async throws {
        guard !deletingAccount, accountOwner == owner,
              let user = Auth.auth().currentUser, user.uid == owner,
              let email = user.email, let apiURL else { throw QueepError.unauthorized }
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email,
                                                                               password: password))
        } catch {
            throw QueepError.server("Não foi possível confirmar sua identidade. Confira a senha e a conexão.")
        }
        guard accountOwner == owner, Auth.auth().currentUser?.uid == owner else { throw QueepError.unauthorized }
        let fresh = try await user.getIDToken(forcingRefresh: true)
        guard accountOwner == owner, Auth.auth().currentUser?.uid == owner else { throw QueepError.unauthorized }
        let api = APIClient(baseURL: apiURL) { fresh }
        do {
            let state = try await api.changeAccountDeletion(version: version, operationID: operationID,
                                                            immediate: immediate, cancel: cancel)
            apply(state, owner: owner)
            if state.status == "deleting" {
                invalidate(owner)
                accountNotice = "Exclusão definitiva solicitada. A remoção continua em segundo plano."
            }
        } catch {
            // A request may have succeeded despite a lost response. Read its actual state.
            try? await refreshAccount(owner: owner)
            throw error
        }
    }

    func token(for owner: String) async throws -> String {
        guard let user = Auth.auth().currentUser, user.uid == owner else { throw QueepError.unauthorized }
        if let group = Auth.auth().userAccessGroup {
            guard try Auth.auth().getStoredUser(forAccessGroup: group)?.uid == owner else {
                throw QueepError.unauthorized
            }
        }
        do { return try await user.getIDToken() }
        catch {
            let failure = error as NSError
            let invalid = [AuthErrorCode.userDisabled, .userNotFound, .invalidUserToken, .userTokenExpired]
            if failure.domain == AuthErrorDomain, invalid.contains(where: { $0.rawValue == failure.code }) {
                invalidate(owner)
            }
            throw error
        }
    }

    func client() -> APIClient? {
        guard let apiURL, let owner = userID else { return nil }
        return APIClient(baseURL: apiURL, onUnauthorized: { [weak self] in
            await self?.handleUnauthorized(owner)
        }) { [weak self] in
            guard let self else { throw QueepError.unauthorized }
            return try await self.token(for: owner)
        }
    }
}
