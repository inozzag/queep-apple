import FirebaseAuth
import QueepCore
import SwiftUI

struct AccountRecoveryView: View {
    let state: AccountStatus
    @Environment(Session.self) private var session
    @State private var password = ""
    @State private var error: String?
    @State private var confirmImmediate = false
    @State private var operationID = UUID()
    @State private var apple = AppleSignInCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                IconTile(asset: "ri-time-line", size: 64, icon: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.canRestore ? "Exclusão agendada" : "Exclusão em andamento")
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("account.recovery.title")
                    if let date = state.deleteAt {
                        Text("Exclusão definitiva: \(date.formatted(date: .long, time: .shortened))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("account.recovery.deadline")
                    }
                    Text(state.canRestore
                         ? "Sua biblioteca está bloqueada e suas referências continuam guardadas. Entrar na conta não cancela a exclusão. Confirme sua identidade e escolha recuperar a conta para voltar a usá-la."
                         : "O prazo para recuperação terminou. A remoção da conta e dos conteúdos continua automaticamente.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state.canRestore {
                    VStack(spacing: 10) {
                        switch session.signInMethod {
                        case .password:
                            SecureField("", text: $password, prompt: Text("Confirme sua senha").foregroundStyle(Theme.inkFaint))
                                .textContentType(.password)
                                .accessibilityLabel("Confirme sua senha")
                                .accessibilityIdentifier("account.recovery.password")
                                .queepField()
                            Button("Cancelar exclusão e recuperar conta") { perform(cancel: true) }
                                .buttonStyle(.queepPrimary)
                                .disabled(password.isEmpty || session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.restore")
                            Button("Excluir definitivamente agora", role: .destructive) { confirmImmediate = true }
                                .buttonStyle(.queep(.destructive))
                                .disabled(password.isEmpty || session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.immediate")
                        case .apple:
                            AppleIDAuthButton(title: "Continuar com a Apple", identifier: "account.recovery.apple") { credential, code in
                                Task { await submit(cancel: true, credential: credential, appleCode: code) }
                            } onError: { error in
                                let text = SocialAuth.message(for: error)
                                if !text.isEmpty { self.error = text }
                            }
                            .disabled(session.deletingAccount)
                            Button("Excluir definitivamente agora", role: .destructive) { confirmImmediate = true }
                                .buttonStyle(.queep(.destructive))
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.immediate")
                        case .google:
                            Button("Cancelar exclusão e recuperar conta") { perform(cancel: true) }
                                .buttonStyle(.queepPrimary)
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.restore")
                            Button("Excluir definitivamente agora", role: .destructive) { confirmImmediate = true }
                                .buttonStyle(.queep(.destructive))
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.immediate")
                        }
                    }
                    .confirmationDialog("Excluir definitivamente? Você não poderá recuperar sua conta.",
                                        isPresented: $confirmImmediate, titleVisibility: .visible) {
                        Button("Excluir definitivamente", role: .destructive) { perform(cancel: false) }
                    }
                }
                if session.deletingAccount { ProgressView().frame(maxWidth: .infinity) }
                if let error {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("account.recovery.error")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        HStack(spacing: 8) {
                            QueepIcon("ri-apple-fill", size: 18, color: Theme.ink)
                            Text("Gerenciar assinatura da Apple")
                        }
                    }
                    .buttonStyle(.queep(.outline))
                    Text("A exclusão da conta não cancela sua assinatura da Apple.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                    Button("Sair da conta") { try? session.signOut() }
                        .buttonStyle(.queep(.quiet))
                        .disabled(session.deletingAccount)
                        .accessibilityIdentifier("account.recovery.signout")
                }
            }
            .padding(32)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func perform(cancel: Bool) {
        Task {
            do {
                switch session.signInMethod {
                case .password:
                    await submit(cancel: cancel, password: password)
                case .apple:
                    let pair = try await apple.credential()
                    await submit(cancel: cancel, credential: pair.0, appleCode: pair.1)
                case .google:
                    await submit(cancel: cancel, credential: try await SocialAuth.googleCredential())
                }
            } catch {
                let text = SocialAuth.message(for: error)
                if !text.isEmpty { self.error = text }
            }
        }
    }

    private func submit(cancel: Bool, password: String? = nil, credential: AuthCredential? = nil,
                        appleCode: String? = nil) async {
        guard let owner = session.accountOwner else { return }
        error = nil
        do {
            try await session.changeAccountDeletion(password: password, credential: credential,
                appleAuthorizationCode: appleCode, owner: owner, version: state.version,
                operationID: operationID, immediate: !cancel, cancel: cancel)
        } catch { self.error = SocialAuth.message(for: error) }
        self.password = ""; operationID = UUID()
    }
}
