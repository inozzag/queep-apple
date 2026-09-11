import SwiftUI
import QueepCore

struct LibraryView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var logoutError: String?

    private var filtered: [Reference] {
        store.searchItems ?? store.items
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                if session.isLocal {
                    Text("Versão de desenvolvimento local")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                if let error = store.error {
                    HStack {
                        Label(error, systemImage: "wifi.exclamationmark").font(.callout)
                        Spacer()
                        Button("Tentar novamente") { Task { await refresh() } }
                    }.padding().background(.quaternary)
                }
                if !store.query.isEmpty {
                    HStack {
                        Text(store.searchItems == nil ? "Busque pelo assunto, pela aparência ou pelo que você lembra."
                             : "Referências mais relevantes do seu acervo · até 10 por busca")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(store.searchItems == nil ? "Buscar" : "Buscar novamente") {
                            Task { await search() }
                        }.disabled(store.searching)
                        Button("Limpar") { store.query = "" }
                    }.padding(.horizontal).padding(.vertical, 8)
                }
                if store.hasPending {
                    Text("Algumas referências ainda aguardam análise ou precisam de uma nova tentativa.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                if let error = store.searchError {
                    Label(error, systemImage: "exclamationmark.magnifyingglass")
                        .font(.callout).foregroundStyle(.secondary).padding()
                }
                if store.searching {
                    ProgressView("Buscando nas suas referências…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.searchError != nil {
                    ContentUnavailableView("Não foi possível buscar", systemImage: "magnifyingglass",
                                           description: Text("Tente novamente em instantes. Suas referências continuam salvas."))
                } else if store.items.isEmpty && store.loading {
                    ProgressView("Carregando suas referências…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(store.searchItems == nil ? "Seu espaço para lembrar" : "Nenhuma referência encontrada",
                              systemImage: store.searchItems == nil ? "bookmark" : "magnifyingglass")
                    } description: {
                        Text(store.searchItems == nil ? "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos."
                             : "Nenhuma correspondência entre os candidatos analisados. Tente descrever de outro jeito.")
                    } actions: {
                        if store.searchItems == nil { Button("Adicionar referência") { store.presentation = .capture(UUID()) }.buttonStyle(.borderedProminent) }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [.init(.adaptive(minimum: 230, maximum: 380), spacing: 16)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(filtered) { reference in
                                Button { store.presentation = .reference(reference) } label: { ReferenceCard(reference: reference) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(reference.displayTitle)
                                    .accessibilityHint("Abrir \(reference.kindLabel.lowercased())")
                            }
                        }.padding()
                        if store.searchItems == nil && store.nextCursor != nil {
                            Button("Carregar mais") {
                                Task {
                                    guard let api = session.client(), let uid = session.userID else { return }
                                    await store.refresh(api, account: uid, more: true)
                                }
                            }.disabled(store.loading).padding()
                        }
                    }.refreshable { await refresh() }
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $store.query, prompt: "Encontre pelo que você lembra")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                        .disabled(store.loading).keyboardShortcut("r")
                    Button { store.presentation = .capture(UUID()) } label: { Label("Adicionar", systemImage: "plus") }
                        .keyboardShortcut("n")
                        .accessibilityIdentifier("library.add")
                    Menu {
                        Button("Assinatura") { store.presentation = .subscription }
                            .accessibilityIdentifier("account.subscription")
                        Button("Sair da conta") {
                            do { try session.signOut() } catch { logoutError = error.localizedDescription }
                        }
                    } label: { Label("Conta", systemImage: "person.crop.circle") }
                }
            }
            .sheet(item: $store.presentation) { presentation in
                switch presentation {
                case .subscription: SubscriptionView()
                case .capture: CaptureView(reference: nil)
                case .reference(let reference):
                    if reference.kind == "image" { ImageDetailView(reference: reference) }
                    else { CaptureView(reference: reference) }
                }
            }
            .alert("Não foi possível sair", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK") { logoutError = nil }
            } message: { Text(logoutError ?? "") }
        }
    }

    private func refresh() async {
        guard let api = session.client(), let uid = session.userID else { return }
        await store.refresh(api, account: uid)
    }

    private func search() async {
        guard let api = session.client(), let uid = session.userID else { return }
        await store.search(api, account: uid)
    }
}

private struct ReferenceCard: View {
    let reference: Reference
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = reference.image {
                RemoteImage(reference: reference, thumbnail: true)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                    .frame(maxHeight: 360).clipped()
                    .accessibilityHidden(true)
            }
            Label(reference.kindLabel, systemImage: reference.kindSymbol)
                .font(.caption).foregroundStyle(.secondary)
            Text(reference.displayTitle).font(.headline).lineLimit(3)
            if !reference.text.isEmpty {
                Text(reference.text).font(.body).foregroundStyle(.secondary).lineLimit(7)
            }
            if let raw = reference.url, let host = URL(string: raw)?.host {
                Text(host).font(.caption).foregroundStyle(.tint).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(reference.statusLabel).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
