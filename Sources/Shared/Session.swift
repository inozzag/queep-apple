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
            Task { @MainActor [weak self] in self?.userID = user?.uid }
        }
        userID = Auth.auth().currentUser?.uid
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
        userID = Auth.auth().currentUser?.uid
    }

    func signOut() throws {
        try Auth.auth().signOut()
        userID = nil
    }

    func token(for owner: String) async throws -> String {
        guard let user = Auth.auth().currentUser, user.uid == owner else { throw QueepError.unauthorized }
        if let group = Auth.auth().userAccessGroup {
            guard try Auth.auth().getStoredUser(forAccessGroup: group)?.uid == owner else {
                throw QueepError.unauthorized
            }
        }
        return try await user.getIDToken()
    }

    func client() -> APIClient? {
        guard let apiURL, let owner = userID else { return nil }
        return APIClient(baseURL: apiURL) { [weak self] in
            guard let self else { throw QueepError.unauthorized }
            return try await self.token(for: owner)
        }
    }
}
