import SwiftUI
import QueepCore

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var logoutError: String?
    @AppStorage("queep.firstSearchHint.dismissed") private var searchHintDismissed = false

    private var filtered: [Reference] { store.searchItems ?? store.items }
    private var searching: Bool { store.searchItems != nil }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.isLocal {
                        Label("Versão de desenvolvimento local", systemImage: "hammer")
                            .font(.caption).foregroundStyle(Color.muted).padding(.horizontal, 4)
                    }
                    if let error = store.error {
                        HStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                            Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Tentar novamente") { Task { await refresh() } }
                        }.card(padding: 14, elevated: false)
                    }
                    if !store.query.isEmpty { SearchHeader(query: store.query, search: { Task { await search() } }) }
                    if store.items.count == 1 && !searching && !searchHintDismissed {
                        HStack(alignment: .top, spacing: 12) {
                            Sparkle()
                            Text("Referência salva. Use a busca da biblioteca para encontrá-la pelo nome ou, depois da análise, pelo assunto e pela aparência.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("onboarding.searchHint")
                            Spacer()
                            Button { searchHintDismissed = true } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Dispensar dica de busca")
                                .accessibilityIdentifier("onboarding.dismissHint")
                        }.card(padding: 14, elevated: false)
                    }
                    if store.searching {
                        SearchSkeleton(columns: columns)
                    } else if store.searchError != nil {
                        ContentUnavailableView("Não foi possível buscar", systemImage: "magnifyingglass",
                                               description: Text("Tente novamente em instantes. Suas referências continuam salvas."))
                    } else if store.items.isEmpty && store.loading && !store.hasLoaded {
                        ProgressView("Carregando suas referências…").frame(maxWidth: .infinity).padding(.top, 80)
                    } else if store.items.isEmpty && store.error != nil && !searching {
                        ContentUnavailableView("Não foi possível carregar a biblioteca", systemImage: "wifi.exclamationmark",
                            description: Text("Toque em Tentar novamente para recuperar suas referências."))
                    } else if store.items.isEmpty && !searching && store.error == nil {
                        FirstUseView(scrolls: false)
                    } else if filtered.isEmpty {
                        ContentUnavailableView {
                            Label(searching ? "Nada parecido por aqui" : "Seu espaço para lembrar",
                                  systemImage: searching ? "sparkle.magnifyingglass" : "bookmark")
                        } description: {
                            Text(searching ? "Nenhuma correspondência entre os candidatos analisados. Tente descrever de outro jeito."
                                 : "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos.")
                        } actions: {
                            if !searching { Button("Adicionar referência") { store.startCapture() }.buttonStyle(.borderedProminent) }
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(filtered) { reference in
                                Button { store.presentation = .reference(reference) } label: {
                                    ReferenceCard(reference: reference, showsAnalysis: searching)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                }
                                .buttonStyle(CardButtonStyle())
                                .accessibilityLabel(reference.displayTitle)
                                .accessibilityValue("\(reference.kindLabel), \(reference.statusLabel)")
                                .accessibilityHint("Abrir \(reference.kindLabel.lowercased())")
                            }
                        }
                        if !searching && store.nextCursor != nil {
                            Button("Carregar mais") {
                                Task {
                                    guard let api = session.client(), let uid = session.userID else { return }
                                    await store.refresh(api, account: uid, more: true)
                                }
                            }.buttonStyle(.bordered).disabled(store.loading).frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: 1280).frame(maxWidth: .infinity)
            }
            .background(Color.canvas)
            .refreshable { await refresh() }
            .navigationTitle("Biblioteca")
            .searchable(text: $store.query, prompt: "Busque pelo que você lembra")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                        .disabled(store.loading).keyboardShortcut("r")
                    Button { store.startCapture() } label: { Label("Adicionar", systemImage: "plus") }
                        .keyboardShortcut("n")
                        .accessibilityIdentifier("library.add")
                    Menu {
                        Button("Como usar o Queep") { store.presentation = .help }
                            .accessibilityIdentifier("account.help")
                        Button("Uso e privacidade") { store.presentation = .usage }
                            .accessibilityIdentifier("account.usage")
                        Button("Assinatura") { store.presentation = .subscription }
                            .accessibilityIdentifier("account.subscription")
                        Button("Sair da conta") {
                            do { try session.signOut() } catch { logoutError = error.localizedDescription }
                        }
                        Divider()
                        Button("Excluir conta", role: .destructive) { store.presentation = .deleteAccount }
                            .accessibilityIdentifier("account.delete")
                    } label: { Label("Conta", systemImage: "person.crop.circle") }
                }
            }
            .sheet(item: $store.presentation) { presentation in
                switch presentation {
                case .usage: UsagePrivacyView()
                case .help: HelpView()
                case .deleteAccount: DeleteAccountView()
                case .subscription: SubscriptionView()
                case .capture: CaptureView(reference: nil, initialKind: store.captureKind)
                case .reference(let reference):
                    if reference.kind == "image" { ImageDetailView(reference: reference) }
                    else if reference.media != nil { MediaDetailView(reference: reference) }
                    else { CaptureView(reference: reference) }
                }
            }
            .alert("Não foi possível sair", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK") { logoutError = nil }
            } message: { Text(logoutError ?? "") }
        }
    }

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [.init(.flexible())] : [.init(.adaptive(minimum: 240, maximum: 360), spacing: 18)]
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

/// The search reads as a conversation with the library: what it is doing, what it found.
private struct SearchHeader: View {
    @Environment(LibraryStore.self) private var store
    let query: String
    let search: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.aiGradient.opacity(0.14)).frame(width: 40, height: 40)
                Sparkle(size: 17)
            }
            VStack(alignment: .leading, spacing: 4) {
                if store.searching {
                    Text("Interpretando “\(query)”").font(.headline)
                    Text("Comparando o significado com o que a IA entendeu das suas referências.")
                        .font(.callout).foregroundStyle(Color.muted)
                } else if let items = store.searchItems {
                    Text(items.isEmpty ? "Nada parecido com “\(query)”" : "\(items.count) \(items.count == 1 ? "referência conferida" : "referências conferidas") por IA")
                        .font(.headline)
                    Text("Referências mais relevantes do seu acervo · até 10 por busca")
                        .font(.callout).foregroundStyle(Color.muted)
                    if store.hasPending {
                        Label("Algumas referências ainda aguardam análise ou precisam de uma nova tentativa.", systemImage: "clock")
                            .font(.caption).foregroundStyle(Color.muted)
                    }
                } else {
                    Text("Pergunte à sua biblioteca").font(.headline)
                    Text("Descreva o assunto, a aparência ou o que você lembra e pressione Enter.")
                        .font(.callout).foregroundStyle(Color.muted)
                }
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(store.searchItems == nil ? "Buscar" : "Buscar novamente", action: search)
                    .buttonStyle(.borderedProminent).disabled(store.searching)
                Button("Limpar") { store.query = "" }.buttonStyle(.bordered)
            }.controlSize(.small)
        }
        .card(padding: 16)
        .overlay(alignment: .bottom) {
            if store.searching {
                Rectangle().fill(Theme.aiGradient).frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .padding(.horizontal, 1).shimmer()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SearchSkeleton: View {
    let columns: [GridItem]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Título da referência").font(.headline)
                    Text("Resumo do que a inteligência artificial entendeu sobre esta referência salva.")
                        .font(.callout)
                    Text("assunto · utilidade").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card(padding: 18)
                .shimmer()
            }
        }
        .accessibilityLabel("Buscando nas suas referências")
    }
}

/// Cards lift slightly under the pointer; the press keeps the same shape.
struct CardButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : hovered ? 1.008 : 1)
            .shadow(color: .black.opacity(hovered ? 0.08 : 0), radius: 16, y: 6)
            .animation(.easeOut(duration: 0.18), value: hovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovered = $0 }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct ReferenceCard: View {
    let reference: Reference
    var showsAnalysis = false

    private var excerpt: String { Markdown.plainText(reference.text) }
    private var host: String? { reference.url.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") } }
    private var hasPicture: Bool { reference.image != nil || reference.kind == "video" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reference.image != nil { picture() }
            else if reference.kind == "video", reference.media != nil { picture(play: true) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    if !hasPicture { KindTile(symbol: reference.kindSymbol, size: 36) }
                    VStack(alignment: .leading, spacing: 4) {
                        if !(reference.kind == "image" && reference.title.isEmpty) {
                            Text(reference.displayTitle).font(.headline)
                                .lineLimit(hasPicture ? 2 : 3).fixedSize(horizontal: false, vertical: true)
                        }
                        if let host, reference.kind == "link" {
                            Text(host).font(.caption).foregroundStyle(.tint).lineLimit(1)
                        } else if let media = reference.media {
                            Text("\(reference.kindLabel) · \(media.durationLabel)").font(.caption).foregroundStyle(Color.muted)
                        } else if reference.kind == "image", reference.title.isEmpty {
                            Text("Imagem").font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                }
                if showsAnalysis, let analysis = reference.analysis, !analysis.summary.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Sparkle(size: 11).padding(.top, 3)
                        Text(analysis.summary).font(.callout).foregroundStyle(Color.muted).lineLimit(4)
                    }
                    if !analysis.topics.isEmpty {
                        HStack(spacing: 6) { ForEach(analysis.topics.prefix(3), id: \.self) { Chip(text: $0) } }
                    }
                } else if reference.kind == "note" || reference.kind == "link", !excerpt.isEmpty, excerpt != reference.displayTitle {
                    Text(excerpt).font(.callout).foregroundStyle(Color.muted).lineLimit(hasPicture ? 2 : 5)
                        .fixedSize(horizontal: false, vertical: true)
                } else if reference.kind == "link", let source = reference.source, !source.title.isEmpty, source.title != reference.displayTitle {
                    Text(source.title).font(.callout).foregroundStyle(Color.muted).lineLimit(2)
                }
                StatusPill(status: reference.status, partial: reference.analysis?.coverage == "partial")
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    /// Covers share one height so rows stay even, like a shelf of cards.
    private func picture(play: Bool = false) -> some View {
        Color.clear.frame(height: 176)
            .overlay { RemoteImage(reference: reference, thumbnail: true, fill: true) }
            .clipped()
            .overlay { if play { Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white).shadow(radius: 6) } }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
