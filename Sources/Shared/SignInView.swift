import FirebaseAuth
import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var create = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                form
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color.white)
        .preferredColorScheme(.light)
        #else
        .background(Color.canvas)
        #endif
    }

    private var header: some View {
        VStack(spacing: 16) {
            QueepLogo(size: 88)
            VStack(spacing: 8) {
                Text("Queep")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.89)
                    .foregroundStyle(Theme.homeInk)
                Text("Salve agora. Encontre depois do jeito que você lembra.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.homePreview)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.isLocal {
                Label("Desenvolvimento local · dados de teste", systemImage: "hammer")
                    .font(.caption).foregroundStyle(Theme.homePreview)
            }
            if let notice = session.accountNotice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(Theme.homePreview)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("auth.notice")
            }
        }
    }

    private var form: some View {
        VStack(spacing: 12) {
            socialButtons
            field("E-mail", text: $email, secure: false)
                .textContentType(.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                #endif
                .accessibilityIdentifier("auth.email")
            field("Senha", text: $password, secure: true)
                .textContentType(create ? .newPassword : .password)
                .accessibilityIdentifier("auth.password")
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task {
                    await run {
                        try await session.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                                 password: password, create: create)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(create ? "Criar conta" : "Entrar")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.homeChrome)
                .background(Theme.homeAccent, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy || email.isEmpty || password.count < 6)
            .opacity(busy || email.isEmpty || password.count < 6 ? 0.5 : 1)
            .accessibilityIdentifier("auth.submit")
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.homeAccent)
                .buttonStyle(.plain)
                .disabled(busy || email.isEmpty)
                .accessibilityIdentifier("auth.reset")
            }
            Button(create ? "Já tenho uma conta" : "Criar uma conta") {
                create.toggle(); error = nil
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.homePreview)
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("auth.toggle")
        }
        .padding(22)
        .homeSurface()
    }

    @ViewBuilder private var socialButtons: some View {
        AppleIDAuthButton(title: create ? "Criar conta com a Apple" : "Entrar com a Apple") { credential, _ in
            Task { await finish(credential: credential) }
        } onError: { fail($0) }
        .disabled(busy)
        Button {
            Task { await finishGoogle() }
        } label: {
            HStack(spacing: 10) {
                if busy { ProgressView().controlSize(.small) }
                GoogleMark()
                Text("Continuar com o Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.homeInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                    .strokeBorder(Theme.homeLine)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("auth.google")
        HStack(spacing: 10) {
            Rectangle().fill(Theme.homeLine).frame(height: 1)
            Text("ou e-mail").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.homePreview)
            Rectangle().fill(Theme.homeLine).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(Theme.homeInk)
        .padding(.horizontal, 16)
        .frame(height: Theme.homeChrome)
        .background(Color(red: 0.965, green: 0.965, blue: 0.965),
                    in: RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                .strokeBorder(Theme.homeLine)
        }
    }

    private func finishGoogle() async {
        await run {
            try await session.signIn(with: try await SocialAuth.googleCredential())
        }
    }

    private func finish(credential: AuthCredential) async {
        await run { try await session.signIn(with: credential) }
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

private struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255))
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}
