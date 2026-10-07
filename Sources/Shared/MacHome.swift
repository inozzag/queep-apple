import SwiftUI
import QueepCore

#if os(macOS)
struct MacLibraryHeader: View {
    @Environment(LibraryStore.self) private var store
    let search: () -> Void
    let refresh: () -> Void
    var selecting = false
    var canSelect = false
    var toggleSelect: () -> Void = {}
    @Binding var addOpen: Bool

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
                HStack(spacing: 8) {
                    if canSelect {
                        LibrarySelectButton(selecting: selecting, action: toggleSelect)
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
        QueepThingsControl(isPresented: $addOpen)
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
