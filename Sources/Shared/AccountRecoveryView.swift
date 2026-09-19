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
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).accessibilityHidden(true)
                Text(state.canRestore ? "Exclusão agendada" : "Exclusão em andamento")
                    .font(.largeTitle.bold()).accessibilityIdentifier("account.recovery.title")
                if let date = state.deleteAt {
                    Text("Exclusão definitiva: \(date.formatted(date: .long, time: .shortened))")
                        .accessibilityIdentifier("account.recovery.deadline")
                }
                Text(state.canRestore
                     ? "Sua biblioteca está bloqueada e suas referências continuam guardadas. Entrar na conta não cancela a exclusão. Confirme sua identidade e escolha recuperar a conta para voltar a usá-la."
                     : "O prazo para recuperação terminou. A remoção da conta e dos conteúdos continua automaticamente.")
                if state.canRestore {
                    Group {
                        switch session.signInMethod {
                        case .password:
                            SecureField("Confirme sua senha", text: $password)
                                .textContentType(.password).textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("account.recovery.password")
                            Button("Cancelar exclusão e recuperar conta") { perform(cancel: true) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(password.isEmpty || session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.restore")
                            Button("Excluir definitivamente agora", role: .destructive) { confirmImmediate = true }
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
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.immediate")
                        case .google:
                            Button("Cancelar exclusão e recuperar conta") { perform(cancel: true) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.restore")
                            Button("Excluir definitivamente agora", role: .destructive) { confirmImmediate = true }
                                .disabled(session.deletingAccount)
                                .accessibilityIdentifier("account.recovery.immediate")
                        }
                    }
                    .confirmationDialog("Excluir definitivamente? Você não poderá recuperar sua conta.",
                                        isPresented: $confirmImmediate, titleVisibility: .visible) {
                        Button("Excluir definitivamente", role: .destructive) { perform(cancel: false) }
                    }
                }
                if session.deletingAccount { ProgressView() }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("account.recovery.error") }
                Link("Gerenciar assinatura da Apple", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Text("A exclusão da conta não cancela sua assinatura da Apple.").font(.caption).foregroundStyle(.secondary)
                Button("Sair da conta") { try? session.signOut() }.disabled(session.deletingAccount)
                    .accessibilityIdentifier("account.recovery.signout")
            }.padding(32).frame(maxWidth: 500)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
