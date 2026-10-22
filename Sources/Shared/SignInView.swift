import FirebaseAuth
import SwiftUI

/// The sign-in form from the Figma "Login": a greeting, Google and Apple side by side, e-mail and
/// password, then Entrar and Criar conta. Both actions use the same two fields.
struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var revealsPassword = false
    @State private var busy: Action?
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password }
    private enum Action: Equatable { case google, apple, signIn, create, reset }

    var body: some View {
        VStack(spacing: 32) {
            Text("Bem-vindo de volta!")
                .font(.system(size: 32))
                .tracking(-0.32)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            status
            providers
            fields
            VStack(spacing: 14) {
                failure
                Button(action: { submit(create: false) }) {
                    HStack(spacing: 8) {
                        if busy == .signIn { ProgressView().controlSize(.small).tint(Theme.ink) }
                        Text("Entrar")
                    }
                }
                .buttonStyle(.queepPrimary)
                .disabled(!canSubmit)
                .accessibilityIdentifier("auth.submit")
                Button(action: { submit(create: true) }) {
                    HStack(spacing: 8) {
                        if busy == .create { ProgressView().controlSize(.small).tint(Theme.ink) }
                        Text("Criar conta")
                    }
                }
                .buttonStyle(.queep(.outline))
                .disabled(!canSubmit)
                .accessibilityHint("Cria uma conta com este e-mail e esta senha.")
                .accessibilityIdentifier("auth.create")
                legal
            }
        }
        .animation(.easeOut(duration: 0.2), value: error)
        .animation(.easeOut(duration: 0.2), value: session.accountNotice)
    }

    private var providers: some View {
        HStack(spacing: 16) {
            Button {
                Task { await run(.google) { try await session.signIn(with: try await SocialAuth.googleCredential()) } }
            } label: {
                HStack(spacing: 8) {
                    if busy == .google {
                        ProgressView().controlSize(.small)
                    } else {
                        Image("BrandGoogle").resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                    }
                    Text("Entrar com Google").font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .buttonStyle(.queep(.outline))
            .accessibilityIdentifier("auth.google")
            AppleIDAuthButton(title: "Entrar com Apple") { credential, _ in
                Task { await run(.apple) { try await session.signIn(with: credential) } }
            } onError: { fail($0) }
        }
        .disabled(busy != nil)
    }

    private var fields: some View {
        VStack(spacing: 20) {
            VStack(spacing: 7) {
                FieldLabel(text: "E-mail")
                TextField("", text: $email, prompt: Text("seu@email.com").foregroundStyle(Theme.inkFaint))
                    .accessibilityLabel("E-mail")
                    .accessibilityIdentifier("auth.email")
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    .queepField(focused: focus == .email)
            }
            VStack(spacing: 7) {
                FieldLabel(text: "Senha")
                passwordField
                    .accessibilityLabel("Senha")
                    .accessibilityIdentifier("auth.password")
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { submit(create: false) }
                    .padding(.trailing, 30)
                    .queepField(focused: focus == .password)
                    .overlay(alignment: .trailing) {
                        Button { revealsPassword.toggle() } label: {
                            QueepIcon(revealsPassword ? "ri-eye-line" : "ri-eye-off-line", size: 18, color: Theme.inkFaint)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 2)
                        .accessibilityLabel(revealsPassword ? "Ocultar senha" : "Mostrar senha")
                    }
            }
            HStack(spacing: 12) {
                Text("Mínimo de 6 caracteres")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 0)
                Button("Esqueci a senha") {
                    Task {
                        await run(.reset) {
                            try await session.sendPasswordReset(to: email)
                            session.accountNotice = "Enviamos um e-mail para redefinir a senha."
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .disabled(busy != nil || email.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("auth.reset")
            }
        }
    }

    @ViewBuilder private var passwordField: some View {
        if revealsPassword {
            TextField("", text: $password, prompt: Text("Sua senha").foregroundStyle(Theme.inkFaint))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } else {
            SecureField("", text: $password, prompt: Text("Sua senha").foregroundStyle(Theme.inkFaint))
        }
    }

    /// What the person needs to know before choosing: the test environment, or why they are here again.
    @ViewBuilder private var status: some View {
        if session.isLocal || session.accountNotice != nil {
            VStack(spacing: 10) {
                if session.isLocal {
                    Text("Desenvolvimento local · dados de teste")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let notice = session.accountNotice {
                    Text(notice)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .surface(.fill, radius: Theme.controlRadius)
                        .accessibilityIdentifier("auth.notice")
                }
            }
            .padding(.top, -12)
        }
    }

    @ViewBuilder private var failure: some View {
        if let error {
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("auth.error")
        }
    }

    /// Shown only where the legal pages are configured; a local build has none to link to.
    @ViewBuilder private var legal: some View {
        if let terms = SubscriptionStore.configuredURL("QueepTermsURL"),
           let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
            Text(LocalizedStringKey(
                "Ao continuar, você aceita os [Termos](\(terms.absoluteString)) e a [Privacidade](\(privacy.absoluteString))."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .tint(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var canSubmit: Bool {
        busy == nil && !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    private func submit(create: Bool) {
        guard canSubmit else { return }
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            await run(create ? .create : .signIn) {
                try await session.signIn(email: address, password: password, create: create)
            }
        }
    }

    private func run(_ action: Action, _ work: () async throws -> Void) async {
        busy = action
        defer { busy = nil }
        do { try await work(); error = nil }
        catch { fail(error) }
    }

    private func fail(_ error: Error) {
        let text = SocialAuth.message(for: error)
        if !text.isEmpty { self.error = text }
    }
}
