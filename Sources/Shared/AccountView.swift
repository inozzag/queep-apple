import QueepCore
import SwiftUI

/// Ajustes. Who you are and your plan first, then the account, the library, billing and help in
/// grouped rows. Free accounts get the PRO card, which opens the journey paywall.
struct AccountView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptions = SubscriptionStore.shared
    @State private var logoutError: String?
    @State private var paywall: PaywallContext?
    #if os(macOS)
    @AppStorage(CloseAndHide.defaultsKey) private var closeAndHide = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    profile
                    planCard
                    accountSection
                    librarySection
                    billingSection
                    SettingsSection(title: "Ajuda") {
                        NavigationLink {
                            HelpView(pushedInSettings: true)
                        } label: {
                            SettingsRow(icon: "ri-question-line", title: "Como usar o Queep")
                        }
                        .buttonStyle(SettingsRowStyle())
                        .accessibilityIdentifier("account.help")
                    }
                    #if os(macOS)
                    SettingsSection(title: "Janela",
                                    footer: "Fechar a janela esconde o Queep do Dock. O menu na barra e o pin de captura continuam.") {
                        SettingsToggleRow(icon: "ri-eye-off-line", title: "Fechar e esconder", isOn: $closeAndHide,
                                          identifier: "settings.closeAndHide")
                    }
                    #endif
                    #if DEBUG
                    SettingsSection(title: "Desenvolvimento") {
                        Button {
                            FeedNotice.scheduleFromSettings(
                                isLocal: session.isLocal,
                                access: SubscriptionStore.shared.access)
                        } label: {
                            SettingsRow(icon: "ri-notification-3-line", title: "Testar aviso do feed", chevron: false)
                        }
                        .buttonStyle(SettingsRowStyle())
                        .accessibilityIdentifier("library.testFeedNotice")
                    }
                    #endif
                    exitSection
                    Text(version)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 600, idealHeight: 740)
        #endif
        .environment(\.colorScheme, .light)
        .task(id: session.userID) {
            if subscriptions.access == nil { await subscriptions.load(session) }
        }
        .journeyPaywall($paywall)
        .alert("Não foi possível sair", isPresented: Binding(
            get: { logoutError != nil },
            set: { if !$0 { logoutError = nil } }
        )) {
            Button("OK") { logoutError = nil }
        } message: { Text(logoutError ?? "") }
    }

    // MARK: Top

    private var header: some View {
        HStack(alignment: .center) {
            Text("Ajustes")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            SettingsCloseButton { dismiss() }
        }
    }

    private var profile: some View {
        HStack(spacing: 16) {
            QueepIcon("ri-user-5-fill", size: 34, color: Theme.ink)
                .frame(width: Theme.chrome, height: Theme.chrome)
                .surface(.plain, radius: Theme.radius)
                .overlay(alignment: .bottom) {
                    if let plan = subscriptions.access?.plan {
                        PlanBadge(plan: plan).offset(y: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(visibleName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(identity?.email ?? "Sem e-mail")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if identity?.emailVerified == false, identity?.email != nil {
                    Text("E-mail ainda não confirmado")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .surface(.fill, radius: Theme.radius)
        .accessibilityElement(children: .combine)
    }

    /// Free: the PRO card. Paid or development: the current plan, which opens Assinatura.
    @ViewBuilder private var planCard: some View {
        if let access = subscriptions.access {
            if access.plan == .free && !access.isDevelopment {
                upgradeCard
            } else {
                NavigationLink {
                    SubscriptionView(pushedInSettings: true)
                } label: {
                    HStack(spacing: 14) {
                        IconTile(asset: "ri-vip-crown-line", fill: Theme.lime.opacity(0.5), color: Theme.forest)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(access.isDevelopment ? "Acesso de desenvolvimento" : "Queep \(access.plan.title)")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                PlanBadge(plan: access.plan)
                            }
                            Text(planDetail(access))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        QueepIcon("ri-arrow-right-s-line", size: 20, color: Theme.inkFaint)
                            .padding(.trailing, 8)
                    }
                    .padding(Theme.chromeInset)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowStyle())
                .padding(Theme.chromeInset)
                .surface(.outline, radius: Theme.radius)
                .accessibilityIdentifier("account.plan")
            }
        }
    }

    private var upgradeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                QueepLockup(scale: 0.8, color: .white)
                PlanBadge(plan: .pro, size: .medium)
            }
            Text("Salve sem pensar em limite e ache qualquer referência com uma busca, no Mac e no iPhone.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
            Button(action: openPaywall) {
                Text("Experimente o Queep \(Text("PRO").fontWeight(.bold))")
            }
            .buttonStyle(.queep(.promo, height: Theme.control, stretches: false))
            .accessibilityIdentifier("account.upgrade")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PromoStage(style: .paywall, anchor: UnitPoint(x: 0.5, y: 0.3))
                .overlay {
                    LinearGradient(colors: [Theme.nightDeep.opacity(0.7), Theme.nightDeep.opacity(0.05)],
                                   startPoint: .leading, endPoint: .trailing)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Sections

    private var accountSection: some View {
        SettingsSection(title: "Conta") {
            NavigationLink {
                AccountNameEditor(name: identity?.displayName ?? "")
            } label: {
                SettingsRow(icon: "ri-user-line", title: "Nome", value: visibleName)
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.name.row")
            NavigationLink {
                AccountEmailEditor(email: identity?.email ?? "")
            } label: {
                SettingsRow(icon: "ri-mail-line", title: "E-mail", value: identity?.email ?? "Sem e-mail")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.email.row")
            NavigationLink {
                AccountPasswordEditor()
            } label: {
                SettingsRow(icon: "ri-lock-password-line", title: "Senha",
                            value: identity?.hasPassword == true ? "Cadastrada" : "Não cadastrada")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.password.row")
            if !session.isLocal {
                NavigationLink {
                    AccountLoginsEditor()
                } label: {
                    SettingsRow(icon: "ri-key-2-line", title: "Logins", value: loginSummary)
                }
                .buttonStyle(SettingsRowStyle())
                .accessibilityIdentifier("account.logins.row")
            }
        }
    }

    private var librarySection: some View {
        SettingsSection(title: "Biblioteca") {
            Button {
                store.show(.archived)
                store.presentation = nil
            } label: {
                SettingsRow(icon: "ri-archive-line", title: "Arquivados")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("library.archived")
            NavigationLink {
                UsagePrivacyView(pushedInSettings: true)
            } label: {
                SettingsRow(icon: "ri-bar-chart-2-line", title: "Uso e privacidade")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.usage")
        }
    }

    private var billingSection: some View {
        SettingsSection(title: "Assinatura e cobrança") {
            NavigationLink {
                SubscriptionView(pushedInSettings: true)
            } label: {
                SettingsRow(icon: "ri-bank-card-line", title: "Assinatura e planos",
                            value: SubscriptionAccess.settingsRowValue(subscriptions.access))
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.subscription")
            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                externalRow(icon: "ri-apple-fill", title: "Gerenciar cobrança na Apple")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.billing")
            Link(destination: URL(string: "https://reportaproblem.apple.com")!) {
                externalRow(icon: "ri-file-list-3-line", title: "Notas fiscais e compras")
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.invoices")
        }
    }

    private var exitSection: some View {
        SettingsSection {
            Button {
                do { try session.signOut() } catch { logoutError = error.localizedDescription }
            } label: {
                SettingsRow(icon: "ri-logout-box-r-line", title: "Sair da conta", chevron: false)
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.signout")
            NavigationLink {
                DeleteAccountView(pushedInSettings: true)
            } label: {
                SettingsRow(icon: "ri-delete-bin-line", title: "Excluir conta", tint: Theme.danger)
            }
            .buttonStyle(SettingsRowStyle())
            .accessibilityIdentifier("account.delete")
        }
    }

    private func externalRow(icon: String, title: String) -> some View {
        HStack(spacing: 0) {
            SettingsRow(icon: icon, title: title, chevron: false)
            QueepIcon("ri-arrow-right-up-line", size: 18, color: Theme.inkFaint)
                .padding(.trailing, 10)
        }
    }

    // MARK: Helpers

    private func openPaywall() {
        #if os(macOS)
        // The Ajustes sheet is too narrow for the card: close it and let the library show it.
        store.paywallReason = "settings"
        store.presentation = nil
        #else
        paywall = PaywallContext(reason: "settings")
        #endif
    }

    private func planDetail(_ access: SubscriptionAccess) -> String {
        if access.isDevelopment { return "A cobrança está desativada neste ambiente" }
        guard let date = access.expiresAt else { return "Vale no Mac e no iPhone" }
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return access.willRenew ? "Renova em \(day)" : "Vale até \(day)"
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

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Queep \(short) (\(build))"
    }
}

// MARK: - Editors

private struct AccountNameEditor: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @State var name: String
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        SettingsPage(title: "Nome", subtitle: "Como o Queep chama você.", close: { library.presentation = nil }) {
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Nome")
                TextField("", text: $name, prompt: Text("Seu nome").foregroundStyle(Theme.inkFaint))
                    .textContentType(.name)
                    .focused($focused)
                    .accessibilityLabel("Nome")
                    .accessibilityIdentifier("account.name")
                    .queepField(focused: focused)
            }
            Button {
                Task {
                    await run {
                        try await session.updateDisplayName(name)
                        notice = "Nome atualizado."
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small).tint(Theme.ink) }
                    Text("Salvar nome")
                }
            }
            .buttonStyle(.queepPrimary)
            .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines) == (session.identity?.displayName ?? ""))
            .accessibilityIdentifier("account.name.save")
            if let error { SettingsNotice(text: error, failure: true) }
            if let notice { SettingsNotice(text: notice) }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do { try await work() } catch { self.error = reportedAccountEditError(error, context: .name) }
    }
}

private struct AccountEmailEditor: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @State var email: String
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsPage(title: "E-mail",
                     subtitle: "A troca só vale depois que você confirmar o link no e-mail novo.",
                     close: { library.presentation = nil }) {
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "E-mail")
                TextField("", text: $email, prompt: Text("seu@email.com").foregroundStyle(Theme.inkFaint))
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    #endif
                    .focused($focused)
                    .accessibilityLabel("E-mail")
                    .accessibilityIdentifier("account.email")
                    .queepField(focused: focused)
            }
            VStack(spacing: 10) {
                Button("Enviar confirmação para o novo e-mail") {
                    Task {
                        await run {
                            try await session.requestEmailChange(email)
                            notice = "Abra o e-mail novo e confirme para concluir a troca."
                        }
                    }
                }
                .buttonStyle(.queepPrimary)
                .disabled(busy || trimmed.isEmpty || trimmed == (session.identity?.email ?? ""))
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
                    .buttonStyle(.queep(.neutral))
                    .disabled(busy || session.identity?.email == nil)
                    .accessibilityIdentifier("account.email.verify")
                }
            }
            if let error { SettingsNotice(text: error, failure: true) }
            if let notice { SettingsNotice(text: notice) }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do { try await work() } catch { self.error = reportedAccountEditError(error, context: .email) }
    }
}

private struct AccountPasswordEditor: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case current, new }
    private var hasPassword: Bool { session.identity?.hasPassword == true }

    var body: some View {
        SettingsPage(title: "Senha", subtitle: "A senha precisa ter pelo menos 6 caracteres.",
                     close: { library.presentation = nil }) {
            if hasPassword {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel(text: "Senha atual")
                    SecureField("", text: $currentPassword)
                        .textContentType(.password)
                        .focused($focus, equals: .current)
                        .accessibilityLabel("Senha atual")
                        .accessibilityIdentifier("account.password.current")
                        .queepField(focused: focus == .current)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: hasPassword ? "Nova senha" : "Cadastrar senha")
                SecureField("", text: $newPassword)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .new)
                    .accessibilityLabel(hasPassword ? "Nova senha" : "Cadastrar senha")
                    .accessibilityIdentifier("account.password.new")
                    .queepField(focused: focus == .new)
            }
            VStack(spacing: 10) {
                Button(hasPassword ? "Atualizar senha" : "Cadastrar senha") {
                    Task {
                        await run {
                            let hadPassword = hasPassword
                            try await session.setPassword(
                                current: hadPassword ? currentPassword : nil,
                                new: newPassword)
                            currentPassword = ""; newPassword = ""
                            notice = hadPassword ? "Senha atualizada." : "Senha cadastrada. Você já pode entrar com e-mail."
                        }
                    }
                }
                .buttonStyle(.queepPrimary)
                .disabled(busy || newPassword.count < 6 || (hasPassword && currentPassword.isEmpty))
                .accessibilityIdentifier("account.password.save")
                Button("Enviar e-mail para redefinir senha") {
                    Task {
                        await run {
                            try await session.sendPasswordReset(to: session.identity?.email ?? "")
                            notice = "Enviamos um e-mail para redefinir a senha."
                        }
                    }
                }
                .buttonStyle(.queep(.neutral))
                .disabled(busy || (session.identity?.email ?? "").isEmpty)
                .accessibilityIdentifier("account.password.reset")
            }
            if let error { SettingsNotice(text: error, failure: true) }
            if let notice { SettingsNotice(text: notice) }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do { try await work() } catch { self.error = reportedAccountEditError(error, context: .password) }
    }
}

private struct AccountLoginsEditor: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        SettingsPage(title: "Logins",
                     subtitle: "Vincule Apple ou Google para entrar no Mac e no iPhone com o mesmo método.",
                     close: { library.presentation = nil }) {
            SettingsSection {
                provider("Apple", icon: "ri-apple-fill", linked: session.identity?.hasApple == true) {
                    if session.identity?.hasApple == true {
                        unlinkButton("apple.com", identifier: "account.apple.unlink")
                    } else {
                        AppleIDAuthButton(title: "Vincular Apple", identifier: "account.apple.link", height: 40) { credential, _ in
                            Task { await run { try await session.link(credential) } }
                        } onError: { fail($0) }
                        .frame(width: 168)
                        .disabled(busy)
                    }
                }
                if SocialAuth.googleAvailable {
                    provider("Google", icon: "ri-google-fill", linked: session.identity?.hasGoogle == true) {
                        if session.identity?.hasGoogle == true {
                            unlinkButton("google.com", identifier: "account.google.unlink")
                        } else {
                            Button("Vincular Google") {
                                Task { await run { try await session.link(try await SocialAuth.googleCredential()) } }
                            }
                            .buttonStyle(.queep(.outline, height: 40, stretches: false))
                            .disabled(busy)
                            .accessibilityIdentifier("account.google.link")
                        }
                    }
                }
            }
            if let error { SettingsNotice(text: error, failure: true) }
        }
    }

    private func provider<Action: View>(_ title: String, icon: String, linked: Bool,
                                        @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 12) {
            IconTile(asset: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Text(linked ? "Vinculado" : "Não vinculado")
                    .font(.system(size: 13))
                    .foregroundStyle(linked ? Theme.forest : Theme.inkSoft)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder private func unlinkButton(_ provider: String, identifier: String) -> some View {
        if session.identity?.canUnlink == true {
            Button("Desvincular", role: .destructive) {
                Task { await run { try await session.unlink(provider: provider) } }
            }
            .buttonStyle(.queep(.destructive, height: 40, stretches: false))
            .disabled(busy)
            .accessibilityIdentifier(identifier)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        self.error = reportedAccountEditError(error, context: .link)
    }
}

/// Account edits must not surface the sign-in sentence. Cancellation stays silent.
private func reportedAccountEditError(_ error: Error, context: AccountEditContext) -> String? {
    let text = AccountEditMessage.resolve(SocialAuth.message(for: error), context: context)
    return text.isEmpty ? nil : text
}
