import FirebaseAuth
import FirebaseCore
import Observation
import QueepCore
import SwiftUI

@MainActor @Observable
final class Session {
    var userID: String?
    var configurationError: String?
    var isLocal = false
    var apiURL: URL?
    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["QUEEP_USE_CLOUD"] != "1" {
            let options = FirebaseOptions(googleAppID: "1:123456789:ios:0123456789abcdef01234567",
                                          gcmSenderID: "123456789")
            options.projectID = "demo-queep"
            options.apiKey = "local-emulator-key"
            FirebaseApp.configure(options: options)
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                try? Auth.auth().signOut()
            }
            apiURL = URL(string: "http://127.0.0.1:8000")
            isLocal = true
        } else { configureCloud() }
        #else
        configureCloud()
        #endif
        guard configurationError == nil else { return }
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
              let url = URL(string: urlString), url.scheme == "https",
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            configurationError = "Esta versão ainda não está configurada para conexão com a nuvem."
            return
        }
        FirebaseApp.configure()
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

    func token() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw QueepError.unauthorized }
        return try await user.getIDToken()
    }

    func client() -> APIClient? {
        guard let apiURL else { return nil }
        return APIClient(baseURL: apiURL) { [weak self] in
            guard let self else { throw QueepError.unauthorized }
            return try await self.token()
        }
    }
}
