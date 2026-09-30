import SwiftUI
import QueepCore

#if os(macOS)
struct MacLibraryHeader: View {
    @Environment(LibraryStore.self) private var store
    let search: () -> Void
    let refresh: () -> Void
    @State private var addOpen = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 24) {
            ZStack {
                HStack(spacing: 16) {
                    HomeBrand()
                    Spacer(minLength: 16)
                    HStack(spacing: 16) {
                        addMenu
                        HomeAccountButton()
                    }
                }
                HStack(spacing: 16) {
                    Button(action: store.showHome) {
                        HomePillLabel(title: "Home", asset: "HomeDashboard").homeSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.home")
                    Button(action: { store.show(.spaces) }) {
                        HomePillLabel(title: "Spaces", asset: "HomeSpaces").homeSurface()
                    }
                    .buttonStyle(.plain)
                    .help("Organizar suas referências em Spaces.")
                    .accessibilityIdentifier("library.spaces")
                    Button(action: { store.show(.archived) }) {
                        Label("Arquivados", systemImage: "archivebox")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.homeInk)
                            .padding(.horizontal, 14).frame(height: Theme.homeChrome)
                            .homeSurface()
                    }
                    .buttonStyle(.plain)
                    .help("Itens ocultos da biblioteca ativa.")
                    .accessibilityIdentifier("library.archived")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HomeSearchField(text: $store.query, width: 400, submit: search)
                    if !store.searchChips.isEmpty {
                        HomeSearchChips(chips: store.searchChips, remove: removeChip)
                            .frame(maxWidth: 450, alignment: .leading)
                    }
                }
                Spacer(minLength: 16)
                HStack(spacing: 16) {
                    if store.hasActiveCollection {
                        Button(action: { store.presentation = .newSpace }) {
                            HomePillLabel(title: "Novo Space", asset: "HomeCreateSpace")
                                .homeSurface()
                        }
                        .buttonStyle(.plain)
                        .help("Criar uma coleção pessoal de referências.")
                        .accessibilityLabel("Novo Space")
                        .accessibilityIdentifier("library.createSpace")
                    }
                    HomeFilterMenu(refresh: refresh)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
        .background(alignment: .leading) {
            HStack {
                Button("Nova nota") { store.startCapture(kind: "note") }.keyboardShortcut("n")
                Button("Atualizar", action: refresh).keyboardShortcut("r")
            }
            .opacity(0).accessibilityHidden(true)
        }
    }

    private var addMenu: some View {
        Button {
            addOpen.toggle()
        } label: {
            HomePillLabel(title: "Queep things", asset: "HomeAdd", accent: true)
                .homeSurface(highlighted: true)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: Theme.homeRadius))
        .popover(isPresented: $addOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                addRow("Nota", "note.text") { store.startCapture(kind: "note") }
                addRow("Post", "quote.bubble") { store.startCapture(kind: "link", intent: "post") }
                addRow("Site", "safari") { store.startCapture(kind: "link", intent: "site") }
                addRow("Imagem", "photo") { store.startCapture(kind: "image") }
                addRow("Áudio ou vídeo", "play.rectangle") { store.startCapture(kind: "media") }
            }
            .padding(8)
            .frame(minWidth: 196)
        }
        .accessibilityIdentifier("library.add")
        .accessibilityLabel("Queep things")
        .help("Guardar uma nota, um post, um site, uma imagem ou um vídeo")
    }

    private func addRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            addOpen = false
            action()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func removeChip(_ term: String) {
        store.removeSearchChip(term)
        if !store.searchChips.isEmpty { search() }
    }
}

struct MacSearchSkeleton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        MasonryLayout(forceColumns: typeSize.isAccessibilitySize ? 1 : nil) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                    .fill(Color.card)
                    .overlay { RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous).strokeBorder(Theme.homeLine) }
                    .frame(height: index.isMultiple(of: 3) ? 280 : 180)
                    .shimmer()
            }
        }
        .accessibilityLabel("Buscando nas suas referências")
    }
}
#endif
