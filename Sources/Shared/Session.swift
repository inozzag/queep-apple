import FirebaseAuth
import FirebaseCore
import Observation
import QueepCore
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
enum SessionAnalytics {
    static var recordSignIn: ((Bool, String, Session) async -> Void)?
    static var reset: (() -> Void)?
}

@MainActor
enum SessionDiagnostics {
    static var userID: String?
    static var onUserChange: ((String?) -> Void)?
}

@MainActor @Observable
final class Session {
    var userID: String? {
        didSet {
            if oldValue != userID {
                planRequirement = nil
                onAccountChange?()
                SessionDiagnostics.userID = userID
                SessionDiagnostics.onUserChange?(userID)
            }
        }
    }
    var onAccountChange: (() -> Void)?
    var configurationError: String?
    var isLocal = false
    var apiURL: URL?
    var preparing = true
    var planRequirement: PlanRequirement?
    var accountNotice: String?
    var accountState: AccountStatus?
    var accountOwner: String?
    var deletingAccount = false
    var profileGeneration = 0
    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        TemporaryMediaFile.cleanOnce()
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
                self.profileGeneration += 1
                if let user { try? await self.refreshAccount(owner: user.uid) }
                else { self.clearAccountState() }
            }
        }
        if let user = Auth.auth().currentUser {
            do { try await refreshAccount(owner: user.uid) }
            catch { accountNotice = "Conecte-se à internet e entre novamente para verificar sua conta." }
        }
        #if DEBUG
        // Explicit UI tests may sign in against the configured Firebase, including CloudDevelopment.
        // A normal launch never passes these arguments, so it does not create or enter an account.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let email = ProcessInfo.processInfo.environment["QUEEP_TEST_EMAIL"],
           let password = ProcessInfo.processInfo.environment["QUEEP_TEST_PASSWORD"],
           isLocal || ProcessInfo.processInfo.arguments.contains("--ui-testing-cloud") {
            let create = ProcessInfo.processInfo.arguments.contains("--ui-testing-create")
            Task {
                if create { try? signOut() }
                try await signIn(email: email, password: password, create: create)
            }
        }
        // Local preview of the empty-library onboarding. A normal launch never passes this.
        if isLocal, ProcessInfo.processInfo.arguments.contains("--preview-onboarding"),
           let email = ProcessInfo.processInfo.environment["QUEEP_PREVIEW_EMAIL"],
           let password = ProcessInfo.processInfo.environment["QUEEP_PREVIEW_PASSWORD"] {
            Task {
                try? signOut()
                do { try await signIn(email: email, password: password, create: true) }
                catch { try? await signIn(email: email, password: password, create: false) }
            }
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

    enum SignInMethod {
        case password, apple, google
        var confirmation: String {
            switch self {
            case .password: "Confirme sua senha"
            case .apple: "Confirme com a Apple"
            case .google: "Confirme com o Google"
            }
        }
    }

    var signInMethod: SignInMethod {
        let ids = Set(Auth.auth().currentUser?.providerData.map(\.providerID) ?? [])
        if ids.contains("apple.com") { return .apple }
        if ids.contains("google.com") { return .google }
        return .password
    }

    func signIn(email: String, password: String, create: Bool) async throws {
        if create {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            try await finishSignIn(created: true)
        } else {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            try await finishSignIn(created: result.additionalUserInfo?.isNewUser == true)
        }
    }

    func signIn(with credential: AuthCredential) async throws {
        let result = try await Auth.auth().signIn(with: credential)
        try await finishSignIn(created: result.additionalUserInfo?.isNewUser == true)
    }

    private func finishSignIn(created: Bool) async throws {
        if let user = Auth.auth().currentUser { try await refreshAccount(owner: user.uid) }
        accountNotice = nil
        await SessionAnalytics.recordSignIn?(created, analyticsMethod, self)
    }

    private var analyticsMethod: String {
        switch signInMethod {
        case .apple: "apple"
        case .google: "google"
        case .password: "email"
        }
    }

    func signOut() throws {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        try Auth.auth().signOut()
        clearAccountState()
        SessionAnalytics.reset?()
    }

    struct Identity: Equatable {
        var displayName: String
        var email: String?
        var emailVerified: Bool
        var photoURL: URL?
        var providers: Set<String>
        var hasPassword: Bool { providers.contains("password") }
        var hasApple: Bool { providers.contains("apple.com") }
        var hasGoogle: Bool { providers.contains("google.com") }
        var canUnlink: Bool { providers.count > 1 }
    }

    var identity: Identity? {
        _ = profileGeneration
        guard let user = Auth.auth().currentUser else { return nil }
        return Identity(
            displayName: user.displayName ?? "",
            email: user.email,
            emailVerified: user.isEmailVerified,
            photoURL: user.photoURL,
            providers: Set(user.providerData.map(\.providerID))
        )
    }

    func reloadIdentity() async {
        try? await Auth.auth().currentUser?.reload()
        profileGeneration += 1
    }

    func updateDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        let change = user.createProfileChangeRequest()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        change.displayName = trimmed.isEmpty ? nil : trimmed
        try await change.commitChanges()
        await reloadIdentity()
    }

    func sendPasswordReset(to email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QueepError.server("Digite o e-mail da conta.") }
        try await Auth.auth().sendPasswordReset(withEmail: trimmed)
    }

    func sendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        try await user.sendEmailVerification()
    }

    func requestEmailChange(_ email: String) async throws {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { throw QueepError.server("Digite um e-mail válido.") }
        try await user.sendEmailVerification(beforeUpdatingEmail: trimmed)
    }

    func setPassword(current: String?, new: String) async throws {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        let password = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count >= 6 else {
            throw QueepError.server("A senha precisa ter pelo menos 6 caracteres.")
        }
        if let current, let email = user.email, identity?.hasPassword == true {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email,
                                                                               password: current))
            try await user.updatePassword(to: password)
        } else if let email = user.email {
            _ = try await user.link(with: EmailAuthProvider.credential(withEmail: email,
                                                                     password: password))
        } else {
            throw QueepError.server("Cadastre um e-mail antes de criar uma senha.")
        }
        await reloadIdentity()
    }

    func link(_ credential: AuthCredential) async throws {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        _ = try await user.link(with: credential)
        await reloadIdentity()
    }

    func unlink(provider: String) async throws {
        guard let user = Auth.auth().currentUser, identity?.canUnlink == true else {
            throw QueepError.server("Mantenha pelo menos um método para entrar na conta.")
        }
        _ = try await user.unlink(fromProvider: provider)
        await reloadIdentity()
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
        #if DEBUG
        await probePlanLimitIfNeeded(api, owner: owner)
        #endif
    }

    #if DEBUG
    private static var didProbePlanLimit = false

    /// One request against an API that enforces plans. HTTP 402 must not open a Sentry issue.
    /// The shared development API runs with billing disabled, so the probe can target another host.
    private func probePlanLimitIfNeeded(_ api: APIClient, owner: String) async {
        guard !Self.didProbePlanLimit,
              ProcessInfo.processInfo.arguments.contains("--sentry-test-402") else { return }
        Self.didProbePlanLimit = true
        let probe: APIClient
        if let raw = ProcessInfo.processInfo.environment["QUEEP_SENTRY_402_URL"],
           let url = URL(string: raw), url.scheme == "https", url.host != nil {
            probe = APIClient(baseURL: url) { [weak self] in
                guard let self else { throw QueepError.unauthorized }
                return try await self.token(for: owner)
            }
        } else {
            probe = api
        }
        var lines: [String] = []
        do {
            _ = try await probe.createSpace(name: "gaz122")
            lines.append("space=created")
        } catch let error as QueepError {
            lines.append("space=\(error)")
        } catch {
            lines.append("space=other \(error)")
        }
        if !lines.contains(where: { $0.contains("planRequired") }) {
            do {
                _ = try await probe.search("gaz122")
                lines.append("search=ok")
            } catch let error as QueepError {
                lines.append("search=\(error)")
            } catch {
                lines.append("search=other \(error)")
            }
        }
        let note = lines.joined(separator: "\n")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sentry-402.txt")
        try? note.data(using: .utf8)?.write(to: url)
        print("sentry-402: \(note)")
        fflush(stdout)
    }
    #endif

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
        SessionAnalytics.reset?()
        accountNotice = "Sua sessão foi encerrada. Entre novamente se sua conta ainda estiver ativa."
    }

    func changeAccountDeletion(password: String? = nil, credential: AuthCredential? = nil,
                               appleAuthorizationCode: String? = nil,
                               owner: String, version: Int,
                               operationID: UUID, immediate: Bool = false, cancel: Bool = false) async throws {
        guard !deletingAccount, accountOwner == owner,
              let user = Auth.auth().currentUser, user.uid == owner,
              let apiURL else { throw QueepError.unauthorized }
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            if let password, let email = user.email {
                _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email,
                                                                                   password: password))
            } else if let credential {
                _ = try await user.reauthenticate(with: credential)
                if immediate, let appleAuthorizationCode {
                    try await Auth.auth().revokeToken(withAuthorizationCode: appleAuthorizationCode)
                }
            } else {
                throw QueepError.unauthorized
            }
        } catch let error as QueepError {
            throw error
        } catch {
            throw QueepError.server("Não foi possível confirmar sua identidade. Tente de novo.")
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

    private func showPlanRequirement(_ requirement: PlanRequirement, owner: String) {
        guard userID == owner else { return }
        planRequirement = requirement
    }

    func client() -> APIClient? {
        guard let apiURL, let owner = userID else { return nil }
        return APIClient(baseURL: apiURL, onUnauthorized: { [weak self] in
            await self?.handleUnauthorized(owner)
        }, onPlanRequired: { [weak self] requirement in
            await self?.showPlanRequirement(requirement, owner: owner)
        }) { [weak self] in
            guard let self else { throw QueepError.unauthorized }
            return try await self.token(for: owner)
        }
    }
}
