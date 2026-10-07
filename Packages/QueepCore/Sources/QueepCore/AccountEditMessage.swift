import Foundation

/// Which account field failed. Sign-in keeps its own fallback; these screens do not reuse it.
public enum AccountEditContext: Sendable {
    case name
    case email
    case password
    case link
}

public enum AccountEditMessage {
    /// Generic failure from `SocialAuth` when the user was trying to sign in.
    public static let signInFallback = "Não foi possível entrar. Tente de novo."

    /// Keeps a specific failure (invalid e-mail, weak password, server text).
    /// Replaces sign-in copy, including Apple and Google sign-in sentences, with field copy.
    /// An empty string is a cancellation and stays empty.
    public static func resolve(_ mapped: String, context: AccountEditContext) -> String {
        let text = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if isSignInCopy(text) { return genericFailure(context) }
        return text
    }

    public static func genericFailure(_ context: AccountEditContext) -> String {
        switch context {
        case .name: "Não foi possível salvar o nome. Tente de novo."
        case .email: "Não foi possível atualizar o e-mail. Tente de novo."
        case .password: "Não foi possível atualizar a senha. Tente de novo."
        case .link: "Não foi possível atualizar o login. Tente de novo."
        }
    }

    public static func isSignInCopy(_ text: String) -> Bool {
        text == signInFallback || text.hasPrefix("Não foi possível entrar")
    }
}
