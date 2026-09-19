import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import QueepCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SocialAuth {
    static var googleAvailable: Bool {
        !(FirebaseApp.app()?.options.clientID ?? "").isEmpty
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "Unable to generate nonce")
            for byte in bytes where remaining > 0 {
                if Int(byte) < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256Nonce(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func appleCredential(from authorization: ASAuthorization, nonce: String) throws -> (AuthCredential, String?) {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw QueepError.server("Não foi possível entrar com a Apple.")
        }
        let code = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
        return (credential, code)
    }

    @MainActor
    static func googleCredential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw QueepError.server("Esta versão ainda não está configurada para entrar com o Google.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        #if os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            throw QueepError.server("Não foi possível abrir o login do Google.")
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        #else
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            throw QueepError.server("Não foi possível abrir o login do Google.")
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        #endif
        guard let idToken = result.user.idToken?.tokenString else {
            throw QueepError.server("Não foi possível entrar com o Google.")
        }
        return GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
    }

    static func message(for error: Error) -> String {
        if isCancellation(error) { return "" }
        let failure = error as NSError
        if failure.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: failure.code) {
            switch code {
            case .weakPassword:
                return "A senha precisa ter pelo menos 6 caracteres."
            case .requiresRecentLogin:
                return "Confirme sua identidade novamente para alterar a conta."
            case .invalidEmail:
                return "Digite um e-mail válido."
            case .emailAlreadyInUse:
                return "Já existe uma conta com este e-mail. Entre com o método que você usou antes."
            case .accountExistsWithDifferentCredential, .credentialAlreadyInUse:
                return "Já existe uma conta com este e-mail. Entre com o método que você usou antes."
            case .providerAlreadyLinked:
                return "Este login já está vinculado a esta conta."
            case .noSuchProvider:
                return "Este login não está vinculado."
            case .networkError:
                return "Sem conexão. Tente de novo em alguns instantes."
            case .userDisabled:
                return "Esta conta foi desativada."
            case .operationNotAllowed:
                return "Este login ainda não está disponível neste ambiente."
            case .invalidCredential, .userMismatch:
                return "Não foi possível confirmar sua identidade. Tente de novo."
            case .userNotFound:
                return "Não encontramos uma conta com este e-mail."
            default:
                break
            }
        }
        if let server = error as? QueepError { return server.localizedDescription }
        return "Não foi possível entrar. Tente de novo."
    }

    static func isCancellation(_ error: Error) -> Bool {
        if let apple = error as? ASAuthorizationError, apple.code == .canceled { return true }
        let failure = error as NSError
        if failure.domain == ASAuthorizationError.errorDomain, failure.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return failure.domain == GIDSignInError.errorDomain && failure.code == GIDSignInError.canceled.rawValue
    }
}

struct AppleIDAuthButton: View {
    var title = "Entrar com a Apple"
    var identifier = "auth.apple"
    var onSuccess: (AuthCredential, String?) -> Void
    var onError: (Error) -> Void = { _ in }
    @State private var coordinator = AppleSignInCoordinator()

    var body: some View {
        Button {
            Task {
                do {
                    let pair = try await coordinator.credential()
                    onSuccess(pair.0, pair.1)
                } catch { onError(error) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.black, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }
}

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<(AuthCredential, String?), Error>?
    private var nonce = ""

    func credential() async throws -> (AuthCredential, String?) {
        if continuation != nil {
            throw QueepError.server("Já há um login da Apple em andamento.")
        }
        nonce = SocialAuth.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SocialAuth.sha256Nonce(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        let nonce = nonce
        let continuation = continuation
        self.continuation = nil
        do { continuation?.resume(returning: try SocialAuth.appleCredential(from: authorization, nonce: nonce)) }
        catch { continuation?.resume(throwing: error) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(macOS)
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #endif
    }
}
