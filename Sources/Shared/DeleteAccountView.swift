import FirebaseAuth
import SwiftUI

struct DeleteAccountView: View {
    /// Pushed inside Ajustes. Back returns to that list; Cancelar still dismisses the sheet.
    var pushedInSettings = false
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var password = ""
    @State private var owner: String?
    @State private var error: String?
    @State private var immediate = false
    @State private var operationID = UUID()
    @State private var version = 0

    var body: some View {
        Group {
            if pushedInSettings {
                detail
            } else {
                NavigationStack { detail }
                    #if os(macOS)
                    .frame(width: 510, height: 660)
                    #endif
            }
        }
        .interactiveDismissDisabled(session.deletingAccount)
        .task { owner = session.userID; version = session.accountState?.version ?? 0 }
    }

    private var detail: some View {
        SettingsPage(title: "Excluir sua conta?",
                     subtitle: "Sua biblioteca será bloqueada agora. Você terá 30 dias para cancelar a exclusão e recuperar suas referências. Depois desse prazo, a conta e os conteúdos serão apagados automaticamente.",
                     closeIdentifier: "account.delete.cancel",
                     closeDisabled: session.deletingAccount,
                     close: close) {
            SettingsSection {
                SettingsToggleRow(icon: "ri-delete-bin-line", title: "Excluir definitivamente agora",
                                  isOn: $immediate, identifier: "account.delete.immediate")
                    .disabled(session.deletingAccount)
                    .onChange(of: immediate) { _, _ in operationID = UUID() }
            }
            if immediate {
                SettingsNotice(text: "A exclusão começa após confirmar sua identidade. Você não poderá recuperar a conta.",
                               failure: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Excluir a conta não cancela uma assinatura da Apple. Para evitar novas cobranças, cancele também sua assinatura.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack(spacing: 8) {
                        QueepIcon("ri-apple-fill", size: 18, color: Theme.ink)
                        Text("Gerenciar assinatura da Apple")
                    }
                }
                .buttonStyle(.queep(.outline))
            }
            confirmControls
            if let error {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.delete.error")
            }
        }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }

    @ViewBuilder private var confirmControls: some View {
        switch session.signInMethod {
        case .password:
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Confirme sua senha")
                SecureField("", text: $password)
                    .textContentType(.password)
                    .accessibilityLabel("Confirme sua senha")
                    .accessibilityIdentifier("account.delete.password")
                    .queepField()
            }
            destructiveButton(enabled: !password.isEmpty) {
                await submit(password: password)
            }
        case .apple:
            Text("A Apple confirma que é você; em seguida a exclusão segue a opção acima.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            AppleIDAuthButton(title: "Continuar com a Apple", identifier: "account.delete.apple") { credential, code in
                Task { await submit(credential: credential, appleCode: code) }
            } onError: { error in
                let text = SocialAuth.message(for: error)
                if !text.isEmpty { self.error = text }
            }
            .disabled(session.deletingAccount || owner != session.userID || SubscriptionStore.shared.busy)
        case .google:
            destructiveButton(enabled: true) {
                await submit(credential: try await SocialAuth.googleCredential())
            }
        }
    }

    private func destructiveButton(enabled: Bool, action: @escaping () async throws -> Void) -> some View {
        Button(role: .destructive) {
            Task { await perform(action) }
        } label: {
            HStack(spacing: 8) {
                if session.deletingAccount { ProgressView().controlSize(.small).tint(.white) }
                Text(immediate ? "Excluir definitivamente" : "Agendar exclusão em 30 dias")
                    .foregroundStyle(.white)
            }
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.button)
            .background(Theme.danger, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || session.deletingAccount || owner != session.userID
                  || SubscriptionStore.shared.busy)
        .opacity(!enabled || session.deletingAccount || owner != session.userID ? 0.45 : 1)
        .accessibilityIdentifier("account.delete.confirm")
    }

    private func submit(password: String? = nil, credential: AuthCredential? = nil, appleCode: String? = nil) async {
        guard let owner else { return }
        await perform {
            try await session.changeAccountDeletion(password: password, credential: credential,
                appleAuthorizationCode: appleCode, owner: owner, version: version,
                operationID: operationID, immediate: immediate)
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard owner != nil else { return }
        error = nil
        do { try await action() }
        catch { self.error = SocialAuth.message(for: error) }
        password = ""
    }
}
