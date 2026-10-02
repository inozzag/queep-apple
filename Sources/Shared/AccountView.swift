import QueepCore
import SwiftUI

struct AccountView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var logoutError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountNameEditor(name: identity?.displayName ?? "")
                    } label: {
                        SettingsRow(title: "Nome", value: visibleName, symbol: "person.fill", color: .blue)
                    }
                    .accessibilityIdentifier("account.name.row")
                    NavigationLink {
                        AccountEmailEditor(email: identity?.email ?? "")
                    } label: {
                        SettingsRow(title: "E-mail", value: identity?.email ?? "Sem e-mail", symbol: "envelope.fill", color: Color(red: 0.2, green: 0.55, blue: 0.95))
                    }
                    .accessibilityIdentifier("account.email.row")
                    if identity?.emailVerified == false, identity?.email != nil {
                        Text("E-mail ainda não confirmado")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    NavigationLink {
                        AccountPasswordEditor()
                    } label: {
                        SettingsRow(title: "Senha", value: identity?.hasPassword == true ? "Cadastrada" : "Não cadastrada", symbol: "lock.fill", color: .indigo)
                    }
                    .accessibilityIdentifier("account.password.row")
                    if !session.isLocal {
                        NavigationLink {
                            AccountLoginsEditor()
                        } label: {
                            SettingsRow(title: "Logins", value: loginSummary, symbol: "key.fill", color: .black)
                        }
                        .accessibilityIdentifier("account.logins.row")
                    }
                }

                Section {
                    Button {
                        store.show(.archived)
                        store.presentation = nil
                    } label: {
                        SettingsRow(title: "Arquivados", value: nil, symbol: "archivebox.fill", color: Color(red: 0.45, green: 0.47, blue: 0.52), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.archived")
                }

                Section("Assinatura e cobrança") {
                    Button {
                        store.presentation = .subscription
                    } label: {
                        SettingsRow(title: "Assinatura e planos", value: nil, symbol: "creditcard.fill", color: .green, chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.subscription")
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        SettingsRow(title: "Gerenciar cobrança na Apple", value: nil, symbol: "dollarsign", color: .orange, chevron: true)
                    }
                    .accessibilityIdentifier("account.billing")
                    Link(destination: URL(string: "https://reportaproblem.apple.com")!) {
                        SettingsRow(title: "Notas fiscais e compras", value: nil, symbol: "doc.text.fill", color: .purple, chevron: true)
                    }
                    .accessibilityIdentifier("account.invoices")
                }

                Section {
                    Button {
                        store.presentation = .help
                    } label: {
                        SettingsRow(title: "Como usar o Queep", value: nil, symbol: "questionmark.circle.fill", color: .blue, chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.help")
                    Button {
                        store.presentation = .usage
                    } label: {
                        SettingsRow(title: "Uso e privacidade", value: nil, symbol: "hand.raised.fill", color: .cyan, chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.usage")
                }

                #if DEBUG
                Section {
                    Button {
                        FeedNotice.scheduleFromSettings(
                            isLocal: session.isLocal,
                            access: SubscriptionStore.shared.access)
                    } label: {
                        SettingsRow(title: "Testar aviso do feed", value: nil, symbol: "bell.fill", color: .orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.testFeedNotice")
                }
                #endif

                Section {
                    Button("Sair da conta") {
                        do { try session.signOut() } catch { logoutError = error.localizedDescription }
                    }
                    .accessibilityIdentifier("account.signout")
                    Button("Excluir conta", role: .destructive) {
                        store.presentation = .deleteAccount
                    }
                    .accessibilityIdentifier("account.delete")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.fill.tertiary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("account.close")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 560, idealHeight: 620)
        #endif
        .alert("Não foi possível sair", isPresented: Binding(
            get: { logoutError != nil },
            set: { if !$0 { logoutError = nil } }
        )) {
            Button("OK") { logoutError = nil }
        } message: { Text(logoutError ?? "") }
    }

    private var identity: Session.Identity? { session.identity }

    private var visibleName: String {
        let trimmed = identity?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let email = identity?.email, let prefix = email.split(separator: "@").first { return String(prefix) }
        return "Sua conta"
    }

    private var loginSummary: String {
        var parts: [String] = []
        if identity?.hasApple == true { parts.append("Apple") }
        if identity?.hasGoogle == true { parts.append("Google") }
        return parts.isEmpty ? "Nenhum" : parts.joined(separator: ", ")
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String?
    let symbol: String
    let color: Color
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(symbol: symbol, color: color)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SettingsGlyph: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct AccountNameEditor: View {
    @Environment(Session.self) private var session
    @State var name: String
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $name)
                    .textContentType(.name)
                    .accessibilityIdentifier("account.name")
            }
            Section {
                Button("Salvar nome") {
                    Task { await run { try await session.updateDisplayName(name) } }
                }
                .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines) == (session.identity?.displayName ?? ""))
                .accessibilityIdentifier("account.name.save")
            }
        }
        .navigationTitle("Nome")
        .alert("Não foi possível atualizar", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await work() } catch { self.error = SocialAuth.message(for: error) }
    }
}

private struct AccountEmailEditor: View {
    @Environment(Session.self) private var session
    @State var email: String
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("E-mail", text: $email)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    #endif
                    .accessibilityIdentifier("account.email")
            } footer: {
                Text("A troca só vale depois que você confirmar o link no e-mail novo.")
            }
            Section {
                Button("Enviar confirmação para o novo e-mail") {
                    Task {
                        await run {
                            try await session.requestEmailChange(email)
                            notice = "Abra o e-mail novo e confirme para concluir a troca."
                        }
                    }
                }
                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || email.trimmingCharacters(in: .whitespacesAndNewlines) == (session.identity?.email ?? ""))
                .accessibilityIdentifier("account.email.change")
                if session.identity?.emailVerified == false {
                    Button("Reenviar verificação do e-mail atual") {
                        Task {
                            await run {
                                try await session.sendVerificationEmail()
                                notice = "Enviamos um e-mail de verificação."
                            }
                        }
                    }
                    .disabled(busy || session.identity?.email == nil)
                    .accessibilityIdentifier("account.email.verify")
                }
            }
            if let notice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("E-mail")
        .alert("Não foi possível atualizar", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch {
            let text = SocialAuth.message(for: error)
            if !text.isEmpty { self.error = text }
        }
    }
}

private struct AccountPasswordEditor: View {
    @Environment(Session.self) private var session
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if session.identity?.hasPassword == true {
                    SecureField("Senha atual", text: $currentPassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("account.password.current")
                }
                SecureField(session.identity?.hasPassword == true ? "Nova senha" : "Cadastrar senha", text: $newPassword)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("account.password.new")
            } footer: {
                Text("A senha precisa ter pelo menos 6 caracteres.")
            }
            Section {
                Button(session.identity?.hasPassword == true ? "Atualizar senha" : "Cadastrar senha") {
                    Task {
                        await run {
                            let hadPassword = session.identity?.hasPassword == true
                            try await session.setPassword(
                                current: hadPassword ? currentPassword : nil,
                                new: newPassword)
                            currentPassword = ""; newPassword = ""
                            notice = hadPassword ? "Senha atualizada." : "Senha cadastrada. Você já pode entrar com e-mail."
                        }
                    }
                }
                .disabled(busy || newPassword.count < 6 || (session.identity?.hasPassword == true && currentPassword.isEmpty))
                .accessibilityIdentifier("account.password.save")
                Button("Enviar e-mail para redefinir senha") {
                    Task {
                        await run {
                            try await session.sendPasswordReset(to: session.identity?.email ?? "")
                            notice = "Enviamos um e-mail para redefinir a senha."
                        }
                    }
                }
                .disabled(busy || (session.identity?.email ?? "").isEmpty)
                .accessibilityIdentifier("account.password.reset")
            }
            if let notice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Senha")
        .alert("Não foi possível atualizar", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch {
            let text = SocialAuth.message(for: error)
            if !text.isEmpty { self.error = text }
        }
    }
}

private struct AccountLoginsEditor: View {
    @Environment(Session.self) private var session
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                labeled("Apple") {
                    if session.identity?.hasApple == true {
                        Text("Vinculado").foregroundStyle(.secondary)
                        if session.identity?.canUnlink == true {
                            Button("Desvincular", role: .destructive) {
                                Task { await run { try await session.unlink(provider: "apple.com") } }
                            }
                            .accessibilityIdentifier("account.apple.unlink")
                        }
                    } else {
                        AppleIDAuthButton(title: "Continuar com a Apple", identifier: "account.apple.link") { credential, _ in
                            Task { await run { try await session.link(credential) } }
                        } onError: { fail($0) }
                        .disabled(busy)
                    }
                }
                if SocialAuth.googleAvailable {
                    labeled("Google") {
                        if session.identity?.hasGoogle == true {
                            Text("Vinculado").foregroundStyle(.secondary)
                            if session.identity?.canUnlink == true {
                                Button("Desvincular", role: .destructive) {
                                    Task { await run { try await session.unlink(provider: "google.com") } }
                                }
                                .accessibilityIdentifier("account.google.unlink")
                            }
                        } else {
                            Button("Vincular Google") {
                                Task { await run { try await session.link(try await SocialAuth.googleCredential()) } }
                            }
                            .disabled(busy)
                            .accessibilityIdentifier("account.google.link")
                        }
                    }
                }
            } footer: {
                Text("Vincule Apple ou Google para entrar no Mac e no iPhone com o mesmo método.")
            }
        }
        .navigationTitle("Logins")
        .alert("Não foi possível atualizar", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            content()
        }
        .padding(.vertical, 4)
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        let text = SocialAuth.message(for: error)
        if !text.isEmpty { self.error = text }
    }
}
