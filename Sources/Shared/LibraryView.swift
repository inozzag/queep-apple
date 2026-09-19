import SwiftUI
import QueepCore

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var logoutError: String?
    @State private var actionError: String?
    @State private var pendingDelete: Reference?
    @State private var macHeaderHeight: CGFloat = 140
    @AppStorage("queep.firstSearchHint.dismissed") private var searchHintDismissed = false

    private var filtered: [Reference] {
        let items = store.searchItems ?? store.items
        guard let kind = store.kindFilter else { return items }
        if kind == "media" { return items.filter { $0.kind == "audio" || $0.kind == "video" } }
        return items.filter { $0.kind == kind }
    }
    private var searching: Bool { store.searchItems != nil }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            libraryStack
            .sheet(item: $store.presentation) { presentation in
                switch presentation {
                case .account: AccountView()
                case .usage: UsagePrivacyView()
                case .help: HelpView()
                case .deleteAccount: DeleteAccountView()
                case .subscription: SubscriptionView()
                case .capture: CaptureView(reference: nil, initialKind: store.captureKind)
                case .reference(let reference):
                    LiveReferenceView(reference: reference) { live in
                        if live.isSocialProfile { ProfileDetailView(reference: live) }
                        else if live.isSocialPost { PostDetailView(reference: live) }
                        else if live.isWebsite { SiteDetailView(reference: live) }
                        else if live.kind == "image" { ImageDetailView(reference: live) }
                        else if live.media != nil { MediaDetailView(reference: live) }
                        else { CaptureView(reference: live) }
                    }
                }
            }
            .alert("Não foi possível sair", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK") { logoutError = nil }
            } message: { Text(logoutError ?? "") }
            .alert("Não foi possível excluir", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: { Text(actionError ?? "") }
            .confirmationDialog("Excluir esta referência dos seus dispositivos?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { reference in
                Button("Excluir \(reference.kindLabel.lowercased())", role: .destructive) { Task { await remove(reference) } }
            } message: { reference in Text(reference.displayTitle) }
        }
    }

    @ViewBuilder private var libraryStack: some View {
        @Bindable var store = store
        #if os(macOS)
        ZStack(alignment: .top) {
            ScrollView {
                libraryContents
                    .padding(.horizontal, 48).padding(.bottom, 36)
                    .padding(.top, max(8, macHeaderHeight))
                    .frame(maxWidth: 1280).frame(maxWidth: .infinity)
            }
            MacLibraryHeader(search: { Task { await search() } }, refresh: { Task { await refresh() } })
                .homeTopBar()
                .onPreferenceChange(HomeTopBarHeightKey.self) { macHeaderHeight = $0 }
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        .hideMacWindowTitle()
        #else
        iPhoneLibrary(search: { Task { await search() } }, refresh: { await refresh() }) {
            libraryContents
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        #endif
    }

    private var libraryContents: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.isLocal {
                Label("Versão de desenvolvimento local", systemImage: "hammer")
                    .font(.caption).foregroundStyle(Color.muted).padding(.horizontal, 4)
            }
            if store.surface == .spaces {
                ContentUnavailableView("Spaces", systemImage: "square.stack.3d.up",
                    description: Text("Pastas com os filtros da busca chegam no próximo passo."))
            } else {
            if let error = store.error {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Tentar novamente") { Task { await refresh() } }
                }.card(padding: 14, elevated: false)
            }
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
                #if os(macOS)
                MacSearchSkeleton()
                #else
                SearchSkeleton(columns: columns)
                #endif
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
                    Label(searching ? "Nada parecido por aqui" : store.kindFilter == nil ? "Seu espaço para lembrar" : "Nada neste filtro",
                          systemImage: searching ? "sparkle.magnifyingglass" : "bookmark")
                } description: {
                    Text(searching ? "Nenhuma correspondência entre os candidatos analisados. Tente descrever de outro jeito."
                         : store.kindFilter == nil
                         ? "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos."
                         : "Esse tipo ainda não está na biblioteca. Queep things guarda o próximo.")
                } actions: {
                    if !searching { Button("Adicionar referência") { store.startCapture() }.buttonStyle(.borderedProminent) }
                }
            } else {
                #if os(macOS)
                MacLibraryCollection(items: filtered, more: !searching && store.nextCursor != nil, loading: store.loading,
                                     open: { store.presentation = .reference($0) },
                                     loadMore: {
                    Task {
                        guard let api = session.client(), let uid = session.userID else { return }
                        await store.refresh(api, account: uid, more: true)
                    }
                }, menu: { cardMenu($0) })
                #else
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(filtered) { reference in
                        LibraryCardCell(reference: reference, open: { store.presentation = .reference(reference) }) {
                            cardMenu(reference)
                        }
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
                #endif
            }
            }
        }
    }

    /// Right-click on the Mac, long-press on iPhone: the basics without opening the item.
    @ViewBuilder private func cardMenu(_ reference: Reference) -> some View {
        Button("Abrir", systemImage: "arrow.up.right.square") { store.presentation = .reference(reference) }
        if let url = reference.url { Button("Copiar link", systemImage: "link") { Clipboard.copy(url) } }
        if !reference.text.isEmpty { Button("Copiar texto", systemImage: "doc.on.doc") { Clipboard.copy(reference.text) } }
        Divider()
        Button("Excluir…", systemImage: "trash", role: .destructive) { pendingDelete = reference }
    }

    private func remove(_ reference: Reference) async {
        guard let api = session.client(), let uid = session.userID else { return }
        do {
            try await api.delete(reference)
            guard session.userID == uid else { return }
            store.discardSearchReference(reference.id)
            await store.refresh(api, account: uid)
        } catch { actionError = error.localizedDescription }
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

/// Keeps detail sheets on the freshest library copy while polling updates the store.
private struct LiveReferenceView<Content: View>: View {
    @Environment(LibraryStore.self) private var store
    let reference: Reference
    @ViewBuilder var content: (Reference) -> Content

    var body: some View {
        content(store.items.first(where: { $0.id == reference.id }) ?? reference)
    }
}


#if os(macOS)
private extension View {
    @ViewBuilder
    func hideMacWindowTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}
#endif
