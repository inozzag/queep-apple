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
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Excluir sua conta?").font(.title2.bold())
                    Text("Sua biblioteca será bloqueada agora. Você terá 30 dias para cancelar a exclusão e recuperar suas referências. Depois desse prazo, a conta e os conteúdos serão apagados automaticamente.")
                    Toggle("Excluir definitivamente agora", isOn: $immediate)
                        .accessibilityIdentifier("account.delete.immediate")
                        .disabled(session.deletingAccount)
                        .onChange(of: immediate) { _, _ in operationID = UUID() }
                    if immediate {
                        Text("A exclusão começa após confirmar sua identidade. Você não poderá recuperar a conta.")
                            .foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Excluir a conta não cancela uma assinatura da Apple. Para evitar novas cobranças, cancele também sua assinatura.")
                        Link("Gerenciar assinatura da Apple", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    confirmControls
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("account.delete.error")
                    }
                }.padding(24).frame(maxWidth: 500)
            }
            .navigationTitle("Excluir conta")
            .toolbar {
                ToolbarItem(placement: pushedInSettings ? .confirmationAction : .cancellationAction) {
                    Button("Cancelar") { close() }.disabled(session.deletingAccount)
                        .accessibilityIdentifier("account.delete.cancel")
                }
            }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }

    @ViewBuilder private var confirmControls: some View {
        switch session.signInMethod {
        case .password:
            SecureField("Confirme sua senha", text: $password)
                .textContentType(.password).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account.delete.password")
            destructiveButton(enabled: !password.isEmpty) {
                await submit(password: password)
            }
        case .apple:
            Text("A Apple confirma que é você; em seguida a exclusão segue a opção acima.")
                .font(.callout).foregroundStyle(.secondary)
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
            HStack {
                if session.deletingAccount { ProgressView().controlSize(.small) }
                Text(immediate ? "Excluir definitivamente" : "Agendar exclusão em 30 dias")
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            .disabled(!enabled || session.deletingAccount || owner != session.userID
                      || SubscriptionStore.shared.busy)
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
