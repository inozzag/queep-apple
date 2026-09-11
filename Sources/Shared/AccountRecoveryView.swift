import SwiftUI
import QueepCore

struct AccountRecoveryView: View {
    let state: AccountStatus
    @Environment(Session.self) private var session
    @State private var password = ""
    @State private var error: String?
    @State private var confirmImmediate = false
    @State private var operationID = UUID()

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
                     ? "Sua biblioteca está bloqueada e suas referências continuam guardadas. Entrar na conta não cancela a exclusão. Confirme sua senha e escolha recuperar a conta para voltar a usá-la."
                     : "O prazo para recuperação terminou. A remoção da conta e dos conteúdos continua automaticamente.")
                if state.canRestore {
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
        guard let owner = session.accountOwner else { return }
        let version = state.version
        Task {
            error = nil
            do {
                try await session.changeAccountDeletion(password: password, owner: owner,
                    version: version, operationID: operationID, immediate: !cancel, cancel: cancel)
            } catch { self.error = error.localizedDescription }
            password = ""; operationID = UUID()
        }
    }
}
