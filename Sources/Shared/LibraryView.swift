import SwiftUI
import QueepCore

struct LibraryView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var logoutError: String?

    private var filtered: [Reference] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return store.items }
        return store.items.filter {
            [$0.title, $0.text, $0.url ?? ""].joined(separator: " ").localizedStandardContains(term)
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                if session.isLocal {
                    Text("Versão de desenvolvimento · busca textual nos itens carregados")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                if let error = store.error {
                    HStack {
                        Label(error, systemImage: "wifi.exclamationmark").font(.callout)
                        Spacer()
                        Button("Tentar novamente") { Task { await refresh() } }
                    }.padding().background(.quaternary)
                }
                if store.items.isEmpty && store.loading {
                    ProgressView("Carregando suas referências…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Seu espaço para lembrar" : "Nenhuma referência encontrada",
                              systemImage: query.isEmpty ? "bookmark" : "magnifyingglass")
                    } description: {
                        Text(query.isEmpty ? "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos."
                             : "Tente outro título ou trecho do texto.")
                    } actions: {
                        if query.isEmpty { Button("Adicionar referência") { store.presentation = .capture(UUID()) }.buttonStyle(.borderedProminent) }
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
                        if store.nextCursor != nil {
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
            .searchable(text: $query, prompt: "Buscar por título ou texto")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                        .disabled(store.loading).keyboardShortcut("r")
                    Button { store.presentation = .capture(UUID()) } label: { Label("Adicionar", systemImage: "plus") }
                        .keyboardShortcut("n")
                        .accessibilityIdentifier("library.add")
                    Menu {
                        Button("Sair da conta") {
                            do { try session.signOut() } catch { logoutError = error.localizedDescription }
                        }
                    } label: { Label("Conta", systemImage: "person.crop.circle") }
                }
            }
            .sheet(item: $store.presentation) { presentation in
                switch presentation {
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
