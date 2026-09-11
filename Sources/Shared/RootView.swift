import SwiftUI
import QueepCore

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let error = session.configurationError {
                ContentUnavailableView("Configuração pendente", systemImage: "icloud.slash",
                                       description: Text(error))
            } else if session.userID != nil {
                LibraryView()
            } else { SignInView() }
        }
        .task(id: session.userID) {
            library.reset(for: session.userID)
            guard let uid = session.userID, let api = session.client() else { return }
            await library.refresh(api, account: uid)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                // Poll only the visible first page; explicit refresh resets pagination.
                if phase == .active && library.items.count <= 40
                    && library.presentation == nil {
                    await library.refresh(api, account: uid)
                }
            }
        }
    }
}

private struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var create = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "bookmark.square.fill")
                    .font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Queep").font(.largeTitle.bold())
                    Text("Salve agora. Encontre depois do jeito que você lembra.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                if session.isLocal {
                    Label("Desenvolvimento local · dados de teste", systemImage: "hammer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 14) {
                    TextField("E-mail", text: $email).textContentType(.username)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth.email")
                    SecureField("Senha", text: $password).textContentType(create ? .newPassword : .password)
                        .accessibilityIdentifier("auth.password")
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                    Button {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                try await session.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                                         password: password, create: create)
                            } catch {
                                #if DEBUG
                                let failure = error as NSError
                                self.error = "Falha local de autenticação (\(failure.domain):\(failure.code))."
                                #else
                                self.error = "Não foi possível entrar. Confira e-mail, senha e conexão."
                                #endif
                            }
                        }
                    } label: {
                        HStack { if busy { ProgressView().controlSize(.small) }; Text(create ? "Criar conta" : "Entrar") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("auth.submit")
                    .disabled(busy || email.isEmpty || password.count < 6)
                    Button(create ? "Já tenho uma conta" : "Criar uma conta") {
                        create.toggle(); error = nil
                    }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("auth.toggle")
                }.textFieldStyle(.roundedBorder)
            }.padding(32).frame(maxWidth: 440)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
