import FirebaseAuth
import SwiftUI

/// The way in: Apple, Google or e-mail, on one surface for signing in and creating an account.
/// `EntryView` decides whether it is a sheet rising from the bottom or a card over the ticker.
struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var step: Step = .options
    @State private var email = ""
    @State private var password = ""
    @State private var create = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Step { case options, email }
    private enum Field: Hashable { case email, password }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .options: options.transition(.opacity)
            case .email: emailForm.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: step)
        .animation(.easeOut(duration: 0.2), value: error)
        .animation(.easeOut(duration: 0.2), value: create)
        .task(id: step) {
            // The field only accepts focus once the form has replaced the buttons.
            guard step == .email else { return }
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { focus = .email }
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Salve agora.\nEncontre depois.")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.89)
                .foregroundStyle(Theme.homeInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            status
            Spacer(minLength: 28)
            VStack(spacing: 10) {
                AppleIDAuthButton(title: "Continuar com a Apple", height: Theme.masterHeight) { credential, _ in
                    Task { await run { try await session.signIn(with: credential) } }
                } onError: { fail($0) }
                googleButton
                Button {
                    error = nil
                    step = .email
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Continuar com e-mail")
                    }
                }
                .buttonStyle(MasterButtonStyle())
                .accessibilityIdentifier("auth.emailStart")
            }
            .disabled(busy)
            failure
            legal
        }
    }

    private var emailForm: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(create ? "Criar sua conta" : "Entrar com e-mail")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.homeInk)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button {
                        focus = nil
                        error = nil
                        step = .options
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.homeInk)
                            .frame(width: 36, height: 36)
                            .background(GalleryStyle.fill, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel("Voltar")
                    .accessibilityIdentifier("auth.back")
                    Spacer(minLength: 0)
                }
            }
            status
            VStack(spacing: 10) {
                field("E-mail", text: $email, .email, identifier: "auth.email")
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                field(create ? "Crie uma senha, 6 caracteres ou mais" : "Senha", text: $password, .password,
                      identifier: "auth.password")
                    .textContentType(create ? .newPassword : .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }
            .padding(.top, 20)
            failure
            Button(action: submit) {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small).tint(Theme.queepThingsInk) }
                    Text(create ? "Criar conta" : "Entrar")
                }
            }
            .buttonStyle(MasterButtonStyle())
            .disabled(!canSubmit)
            .padding(.top, 14)
            .accessibilityIdentifier("auth.submit")
            HStack(spacing: 0) {
                if !create {
                    Button("Esqueci a senha") {
                        Task {
                            await run {
                                try await session.sendPasswordReset(to: email)
                                error = nil
                                session.accountNotice = "Enviamos um e-mail para redefinir a senha."
                            }
                        }
                    }
                    .disabled(busy || email.isEmpty)
                    .accessibilityIdentifier("auth.reset")
                    Spacer(minLength: 12)
                }
                Button(create ? "Já tenho uma conta" : "Criar uma conta") {
                    create.toggle()
                    error = nil
                }
                .disabled(busy)
                .accessibilityIdentifier("auth.toggle")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.homePreview)
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
    }

    /// What the person needs to know before choosing: the test environment, or why they are here again.
    @ViewBuilder private var status: some View {
        if session.isLocal {
            Label("Desenvolvimento local · dados de teste", systemImage: "hammer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GalleryStyle.secondary)
                .padding(.top, 12)
        }
        if let notice = session.accountNotice {
            Text(notice)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.homePreview)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(GalleryStyle.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 14)
                .accessibilityIdentifier("auth.notice")
        }
    }

    @ViewBuilder private var failure: some View {
        if let error {
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.70, green: 0.16, blue: 0.14))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
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
                .foregroundStyle(GalleryStyle.secondary)
                .tint(Theme.homeInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    private var googleButton: some View {
        Button {
            Task { await run { try await session.signIn(with: try await SocialAuth.googleCredential()) } }
        } label: {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image("BrandGoogle")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
                Text("Continuar com o Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.homeInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.masterHeight)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                    .strokeBorder(Theme.homeLine)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth.google")
    }

    /// The identifier goes on the control itself so UI tests keep finding a text field.
    private func field(_ title: String, text: Binding<String>, _ kind: Field, identifier: String) -> some View {
        Group {
            if kind == .password {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .accessibilityIdentifier(identifier)
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .foregroundStyle(Theme.homeInk)
        .focused($focus, equals: kind)
        .padding(.horizontal, 16)
        .frame(height: Theme.masterHeight)
        .background(GalleryStyle.fill, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                .strokeBorder(focus == kind ? Theme.queepThingsInk : Color.clear, lineWidth: 1.5)
        }
        // The text control is only as tall as its line; the whole surface should take the tap.
        .contentShape(Rectangle())
        .onTapGesture { focus = kind }
    }

    private var canSubmit: Bool {
        !busy && !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            await run {
                try await session.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                         password: password, create: create)
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await work(); error = nil }
        catch { fail(error) }
    }

    private func fail(_ error: Error) {
        let text = SocialAuth.message(for: error)
        if !text.isEmpty { self.error = text }
    }
}
