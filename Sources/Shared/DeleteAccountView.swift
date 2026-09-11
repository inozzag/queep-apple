import SwiftUI

struct DeleteAccountView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var owner: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Excluir sua conta?").font(.title2.bold())
                    Text("Suas notas, links, imagens e análises serão removidos. O acesso será encerrado em todos os seus dispositivos. Essa ação não pode ser desfeita.")
                    Text("A remoção continua em segundo plano após a confirmação. Você pode fechar o app.")
                        .foregroundStyle(.secondary)
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
                            do { try await session.deleteAccount(password: password, owner: owner) }
                            catch { self.error = error.localizedDescription }
                            password = ""
                        }
                    } label: {
                        HStack {
                            if session.deletingAccount { ProgressView().controlSize(.small) }
                            Text("Excluir minha conta")
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
        .task { owner = session.userID }
        #if os(macOS)
        .frame(width: 510, height: 610)
        #endif
    }
}
