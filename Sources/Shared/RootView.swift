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
            } else if session.preparing {
                ProgressView("Abrindo sua biblioteca…")
            } else if let state = session.accountState, !state.isActive {
                AccountRecoveryView(state: state)
            } else if session.userID != nil {
                LibraryView()
            } else { SignInView() }
        }
        .task(id: SyncKey(userID: session.userID, owner: session.accountOwner, active: phase == .active)) {
            library.reset(for: session.userID)
            if session.userID == nil { await SubscriptionStore.shared.clearSession(session) }
            guard phase == .active else { return }
            if session.userID == nil, let owner = session.accountOwner {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    await session.handleUnauthorized(owner)
                }
                return
            }
            guard let uid = session.userID, let api = session.client() else { return }
            await library.refresh(api, account: uid)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                // Poll only the visible first page; explicit refresh resets pagination.
                if phase == .active && library.items.count <= 40
                    && library.presentation == nil {
                    await library.refresh(api, account: uid)
                } else if phase == .active {
                    // Account closure must also dismiss details and capture sheets on other devices.
                    await session.handleUnauthorized(uid)
                }
            }
        }
    }

    private struct SyncKey: Equatable {
        let userID: String?
        let owner: String?
        let active: Bool
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
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.aiGradient.opacity(0.16)).frame(width: 60, height: 60)
                    Image(systemName: "bookmark.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.aiGradient)
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Queep").font(.largeTitle.bold())
                    Text("Salve agora. Encontre depois do jeito que você lembra.")
                        .font(.title3).foregroundStyle(Color.muted)
                }
                if session.isLocal {
                    Label("Desenvolvimento local · dados de teste", systemImage: "hammer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = session.accountNotice {
                    Text(notice).font(.callout).accessibilityIdentifier("auth.notice")
                }
                VStack(spacing: 14) {
                    TextField("E-mail", text: $email).textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        #endif
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
                                self.error = "Falha de autenticação (\(failure.domain):\(failure.code))."
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
                }.textFieldStyle(.roundedBorder).card(padding: 20)
            }.padding(32).frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
    }
}
