import SwiftUI

struct DeleteAccountView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var owner: String?
    @State private var error: String?
    @State private var immediate = false
    @State private var operationID = UUID()
    @State private var version = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Excluir sua conta?").font(.title2.bold())
                    Text("Sua biblioteca será bloqueada agora. Você terá 30 dias para cancelar a exclusão e recuperar suas referências. Depois desse prazo, a conta e os conteúdos serão apagados automaticamente.")
                    Toggle("Excluir definitivamente agora", isOn: $immediate)
                        .accessibilityIdentifier("account.delete.immediate")
                        .disabled(session.deletingAccount)
                        .onChange(of: immediate) { _, _ in operationID = UUID() }
                    if immediate {
                        Text("A exclusão começa após confirmar a senha. Você não poderá recuperar a conta.")
                            .foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Excluir a conta não cancela uma assinatura da Apple. Para evitar novas cobranças, cancele também sua assinatura.")
                        Link("Gerenciar assinatura da Apple", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    SecureField("Confirme sua senha", text: $password)
                        .textContentType(.password).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("account.delete.password")
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("account.delete.error")
                    }
                    Button(role: .destructive) {
                        guard let owner else { return }
                        Task {
                            error = nil
                            do {
                                try await session.changeAccountDeletion(password: password, owner: owner,
                                    version: version, operationID: operationID, immediate: immediate)
                            }
                            catch { self.error = error.localizedDescription }
                            password = ""
                        }
                    } label: {
                        HStack {
                            if session.deletingAccount { ProgressView().controlSize(.small) }
                            Text(immediate ? "Excluir definitivamente" : "Agendar exclusão em 30 dias")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                        .disabled(password.isEmpty || session.deletingAccount || owner != session.userID
                                  || SubscriptionStore.shared.busy)
                        .accessibilityIdentifier("account.delete.confirm")
                }.padding(24).frame(maxWidth: 500)
            }
            .navigationTitle("Excluir conta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(session.deletingAccount)
                        .accessibilityIdentifier("account.delete.cancel")
                }
            }
        }
        .interactiveDismissDisabled(session.deletingAccount)
        .task { owner = session.userID; version = session.accountState?.version ?? 0 }
        #if os(macOS)
        .frame(width: 510, height: 660)
        #endif
    }
}
