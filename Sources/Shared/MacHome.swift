import SwiftUI
import QueepCore

#if os(macOS)
struct MasonryLayout: Layout {
    var spacing: CGFloat = Theme.homeGap
    var forceColumns: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let columns = columnCount(for: width)
        guard width > 0, !subviews.isEmpty else { return CGSize(width: width, height: 0) }
        let columnWidth = self.columnWidth(in: width, columns: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)
        for subview in subviews {
            let column = shortest(heights)
            let size = subview.sizeThatFits(.init(width: columnWidth, height: nil))
            heights[column] += size.height + spacing
        }
        return CGSize(width: width, height: max(0, (heights.max() ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columnCount(for: bounds.width)
        let columnWidth = self.columnWidth(in: bounds.width, columns: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)
        for subview in subviews {
            let column = shortest(heights)
            let size = subview.sizeThatFits(.init(width: columnWidth, height: nil))
            let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY + heights[column]),
                proposal: .init(width: columnWidth, height: size.height)
            )
            heights[column] += size.height + spacing
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        if let forceColumns { return max(1, forceColumns) }
        if width < 540 { return 1 }
        if width < 820 { return 2 }
        if width < 1_100 { return 3 }
        return 4
    }

    private func columnWidth(in width: CGFloat, columns: Int) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func shortest(_ heights: [CGFloat]) -> Int {
        heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
    }
}

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
        .padding(.horizontal, 48).padding(.top, 16).padding(.bottom, 18)
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

struct MacLibraryCollection<MenuContent: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let items: [Reference]
    let more: Bool
    let loading: Bool
    let selecting: Bool
    let selectedIDs: Set<String>
    let open: (Reference) -> Void
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent

    var body: some View {
        VStack(spacing: 18) {
            MasonryLayout(forceColumns: typeSize.isAccessibilitySize ? 1 : nil) {
                ForEach(items) { reference in
                    LibraryCardCell(reference: reference, open: { open(reference) }) {
                        menu(reference)
                    }
                    .id(reference.id)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(alignment: .topTrailing) {
                        if selecting {
                            Image(systemName: selectedIDs.contains(reference.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(selectedIDs.contains(reference.id) ? Color.accentColor : .secondary)
                                .padding(10).accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .scrollTargetLayout()
            if more {
                Button("Carregar mais", action: loadMore)
                    .buttonStyle(.bordered).disabled(loading).frame(maxWidth: .infinity)
            }
        }
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
