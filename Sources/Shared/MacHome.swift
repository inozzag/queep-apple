import SwiftUI
import QueepCore

#if os(macOS)
/// Gallery header from the Figma: lockup, Gallery and Spaces, search with screen capture and
/// filters, Queep things, and the account with its plan. All of it floats in one glass bar,
/// like the iPhone's nav, with the library visible behind it.
struct MacLibraryHeader: View {
    @Environment(LibraryStore.self) private var store
    let search: () -> Void
    let refresh: () -> Void
    @Binding var addOpen: Bool
    @State private var width: CGFloat = 1315

    private let metrics = ChromeMetrics.compact
    /// 12pt between groups on a roomy window, 6 when the window is near its minimum.
    private var gap: CGFloat { width < 1200 ? 6 : 12 }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: gap) {
                QueepLockup(scale: 0.68)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 8)
                LibraryTabs()
                HomeSearchField(text: $store.query, height: metrics.control, radius: metrics.controlRadius,
                                submit: search) {
                    Button { MacCapture.shared.captureScreen() } label: {
                        QueepIcon("ri-focus-mode", size: metrics.icon, color: Theme.ink)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Capturar uma área da tela · ⌘⇧7")
                    .accessibilityLabel("Capturar tela")
                    .accessibilityIdentifier("library.captureScreen")
                    HomeFilterMenu(refresh: refresh, icon: metrics.icon)
                }
                .frame(minWidth: 180)
                QueepThingsControl(isPresented: $addOpen)
                HomeAccountButton(size: metrics.control)
            }
            .padding(metrics.inset)
            .floatingSurface(radius: metrics.containerRadius)
            .environment(\.chromeMetrics, metrics)
            if kindTitle != nil || !store.searchChips.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if let kindTitle {
                        Button { store.kindFilter = nil } label: {
                            GalleryChip(title: kindTitle, symbol: "ri-close-line", selected: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remover filtro \(kindTitle)")
                        .accessibilityIdentifier("library.kindFilter")
                    }
                    if !store.searchChips.isEmpty {
                        HomeSearchChips(chips: store.searchChips, remove: removeChip)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pageMargin(for: width))
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, value in width = value }
            }
        }
        .background(alignment: .leading) {
            HStack {
                Button("Nova nota") { store.startCapture(kind: "note") }.keyboardShortcut("n")
                Button("Atualizar", action: refresh).keyboardShortcut("r")
            }
            .opacity(0).accessibilityHidden(true)
        }
    }

    private var kindTitle: String? {
        switch store.kindFilter {
        case "note": "Notas"
        case "link": "Links"
        case "image": "Imagens"
        case "media": "Áudio e vídeo"
        default: nil
        }
    }

    private func removeChip(_ term: String) {
        store.removeSearchChip(term)
        if !store.searchChips.isEmpty { search() }
    }
}
#endif
