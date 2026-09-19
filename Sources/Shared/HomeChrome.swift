import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeBrand: View {
    var body: some View {
        Text("Queep")
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.89)
            .foregroundStyle(Color(red: 41 / 255, green: 37 / 255, blue: 33 / 255))
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Queep")
    }
}

/// Nine-dot mark from `queep-logo.svg`, used on sign-in and the Mac menu bar.
struct QueepLogo: View {
    var size: CGFloat = 72

    var body: some View {
        Image("HomeLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(580 / 548, contentMode: .fit)
            .frame(width: size, height: size * 548 / 580)
            .accessibilityHidden(true)
    }
}

struct HomeTopBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// White at the top of the chrome, fading to clear so cards can sit behind the bar.
struct HomeTopScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.42),
                .init(color: .white.opacity(0.55), location: 0.72),
                .init(color: .white.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

extension View {
    func homeTopBar(fade: CGFloat = 56) -> some View {
        background(alignment: .top) {
            Color.clear
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        HomeTopScrim()
                            .frame(width: geo.size.width, height: geo.size.height + fade, alignment: .top)
                    }
                }
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: HomeTopBarHeightKey.self, value: geo.size.height)
            }
        }
    }
}

struct HomeGlyph: View {
    let asset: String
    var size: CGFloat = 20
    var original = false
    var color: Color = Theme.homePreview

    var body: some View {
        Group {
            if original {
                Image(asset).resizable().renderingMode(.original)
            } else {
                Image(asset).resizable().renderingMode(.template)
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct HomePillLabel: View {
    let title: String
    let asset: String
    var accent = false

    var body: some View {
        HStack(spacing: 16) {
            HomeGlyph(asset: asset, original: accent)
            Text(title)
                .font(.system(size: 13, weight: accent ? .semibold : .regular))
                .foregroundStyle(accent ? Theme.homeAccent : Theme.homePreview)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16.4)
        .frame(height: Theme.homeChrome)
        .contentShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
    }
}

struct HomeIconChrome: View {
    let asset: String
    var size: CGFloat = 20
    var chrome: CGFloat = Theme.homeChrome

    var body: some View {
        HomeGlyph(asset: asset, size: size)
            .frame(width: chrome, height: chrome)
            .contentShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
    }
}

struct HomeSearchField: View {
    @Binding var text: String
    var width: CGFloat?
    var height: CGFloat = Theme.homeChrome
    var autofocus = false
    var surfaced = true
    var submit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            HomeGlyph(asset: "HomeSearch")
            TextField("Busque na sua língua...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.homeInk)
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("Busca da biblioteca")
                .accessibilityIdentifier("library.search")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .modifier(HomeOptionalSurface(enabled: surfaced))
        .onAppear { if autofocus { focused = true } }
    }
}

struct HomeSearchChips: View {
    let chips: [String]
    var remove: (String) -> Void

    var body: some View {
        HomeChipWrap(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button {
                    remove(chip)
                } label: {
                    HStack(spacing: 8) {
                        Image("HomeClose").resizable().renderingMode(.template)
                            .foregroundStyle(Theme.homePreview)
                            .frame(width: 11, height: 11)
                            .accessibilityHidden(true)
                        Text(chip)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.homePreview)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .homeSurface()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remover \(chip)")
            }
        }
    }
}

private struct HomeChipWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                x = 0
                y += row + spacing
                row = 0
            }
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: limit.isFinite ? limit : maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct HomeFilterMenu: View {
    @Environment(LibraryStore.self) private var store
    let refresh: () -> Void
    var chrome: CGFloat = Theme.homeChrome
    var icon: CGFloat = 20
    var surfaced = true

    var body: some View {
        Menu {
            Button("Tudo") { store.kindFilter = nil }
            Button("Notas") { store.kindFilter = "note" }
            Button("Links") { store.kindFilter = "link" }
            Button("Imagens") { store.kindFilter = "image" }
            Button("Áudio e vídeo") { store.kindFilter = "media" }
            Divider()
            Button("Atualizar", action: refresh)
        } label: {
            HomeIconChrome(asset: "HomeEqualizer", size: icon, chrome: chrome)
                .modifier(HomeOptionalSurface(enabled: surfaced))
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .accessibilityLabel("Filtrar referências")
        .accessibilityIdentifier("library.filter")
        .help(filterHelp)
    }

    private var filterHelp: String {
        switch store.kindFilter {
        case "note": "Mostrando notas"
        case "link": "Mostrando links"
        case "image": "Mostrando imagens"
        case "media": "Mostrando áudio e vídeo"
        default: "Filtrar por tipo"
        }
    }
}

struct HomeAccountButton: View {
    @Environment(LibraryStore.self) private var store
    var chrome: CGFloat = Theme.homeChrome
    var surfaced = true

    var body: some View {
        Button {
            store.presentation = .account
        } label: {
            HomeIconChrome(asset: "HomeUser", chrome: chrome)
                .modifier(HomeOptionalSurface(enabled: surfaced))
        }
        .buttonStyle(.plain)
        .help("Conta")
        .accessibilityLabel("Conta")
        .accessibilityIdentifier("person.crop.circle")
    }
}

private struct HomeOptionalSurface: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.homeSurface() } else { content }
    }
}
#if os(iOS)
enum MobileNavMode: Equatable {
    case standard, add, search
}

private enum QueepGlassShape {
    case circle, capsule, card
}

private struct QueepGlass: ViewModifier {
    var shape: QueepGlassShape = .capsule

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                content.glassEffect(.regular.interactive(), in: Circle())
            case .capsule:
                content.glassEffect(.regular, in: Capsule())
            case .card:
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.homeNavMenuRadius, style: .continuous))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: fallback)
                .overlay(fallback.strokeBorder(Color.white.opacity(0.45)))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        }
    }

    private var fallback: RoundedRectangle {
        let radius: CGFloat = switch shape {
        case .circle, .capsule: Theme.homeNav / 2
        case .card: Theme.homeNavMenuRadius
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

private extension View {
    func queepGlass(_ shape: QueepGlassShape = .capsule) -> some View {
        modifier(QueepGlass(shape: shape))
    }
}

struct MobileLibraryHeader: View {
    let refresh: () -> Void

    var body: some View {
        HStack {
            HomeBrand()
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                HomeFilterMenu(refresh: refresh, chrome: 48, icon: 22, surfaced: false)
                    .queepGlass(.circle)
                HomeAccountButton(chrome: 48, surfaced: false)
                    .queepGlass(.circle)
            }
        }
        .padding(.horizontal, Theme.homeNavInset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct iPhoneLibrary<Content: View>: View {
    @Environment(LibraryStore.self) private var store
    let search: () -> Void
    let refresh: () async -> Void
    @ViewBuilder var content: Content
    @State private var mode: MobileNavMode = .standard
    @State private var headerHeight: CGFloat = 72

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                content
                    .padding(.horizontal, Theme.homeNavInset)
                    .padding(.top, max(8, headerHeight))
                    .padding(.bottom, Theme.homeNav + Theme.homeNavBottom + 24)
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity)
            }
            .refreshable { await refresh() }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer(minLength: 0)
                MobileLibraryNav(mode: $mode, search: search)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                MobileLibraryHeader(refresh: { Task { await refresh() } })
                if !store.searchChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HomeSearchChips(chips: store.searchChips, remove: removeChip)
                            .padding(.horizontal, Theme.homeNavInset)
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .homeTopBar()
        }
        .onPreferenceChange(HomeTopBarHeightKey.self) { headerHeight = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.presentation != nil) { _, open in
            if open { mode = .standard }
        }
    }

    private func removeChip(_ term: String) {
        store.removeSearchChip(term)
        if !store.searchChips.isEmpty { search() }
    }
}

struct MobileLibraryNav: View {
    @Environment(LibraryStore.self) private var store
    @Binding var mode: MobileNavMode
    let search: () -> Void
    @State private var keyboardVisible = false

    private var navWidth: CGFloat {
        UIScreen.main.bounds.width - Theme.homeNavInset * 2
    }

    private var tabsWidth: CGFloat {
        max(0, navWidth - Theme.homeNav * 2 - Theme.homeNavGap * 2)
    }

    var body: some View {
        Group {
            if mode == .add {
                addBar
            } else if mode == .search {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: Theme.homeNavGap) { searchBar }
                        .frame(width: navWidth)
                } else {
                    searchBar.frame(width: navWidth, alignment: .leading)
                }
            } else if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: Theme.homeNavGap) { standardBar }
                    .frame(width: navWidth)
            } else {
                standardBar.frame(width: navWidth)
            }
        }
        .frame(width: navWidth)
        .padding(.horizontal, Theme.homeNavInset)
        .padding(.bottom, Theme.homeNavBottom)
        .animation(.spring(duration: 0.22, bounce: 0), value: mode)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: mode) { _, value in
            if value != .search { dismissKeyboard() }
        }
    }

    private var standardBar: some View {
        HStack(alignment: .bottom, spacing: Theme.homeNavGap) {
            tabGroup(width: tabsWidth)
            chromeButton(asset: "HomeAdd", identifier: "library.add", label: "Adicionar") {
                mode = .add
            }
            chromeButton(asset: "HomeSearch", identifier: "library.nav.search", label: "Buscar") {
                mode = .search
            }
        }
        .frame(width: navWidth)
    }

    private var addBar: some View {
        HStack(alignment: .bottom, spacing: Theme.homeNavGap) {
            tabGroup(width: nil)
            addMenu
        }
        .frame(width: navWidth, alignment: .center)
    }

    private func tabGroup(width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            tab("Home", "HomeDashboard", .home, "library.home", flexible: width != nil)
            tab("Spaces", "HomeSpaces", .spaces, "library.spaces", flexible: width != nil)
        }
        .padding(5)
        .frame(width: width, height: Theme.homeNav)
        .queepGlass(.capsule)
    }

    private var addMenu: some View {
        VStack(spacing: 2) {
            addRow("Posts", "HomeHashtag", "library.add.post") {
                store.startCapture(kind: "link", intent: "post")
            }
            addRow("Files", "HomeAttachment", "library.add.files") {
                store.startCapture(kind: "image")
            }
            addRow("Sites", "HomeLink", "library.add.site") {
                store.startCapture(kind: "link", intent: "site")
            }
            addRow("Notes", "HomeFile", "library.add.note") {
                store.startCapture(kind: "note")
            }
            Button {
                mode = .standard
            } label: {
                HStack(spacing: 10) {
                    HomeGlyph(asset: "HomeBack", size: 18)
                    Text("Voltar").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.homePreview)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")
            .accessibilityIdentifier("library.nav.back")
        }
        .padding(8)
        .frame(width: 188)
        .queepGlass(.card)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.homeNavGap) {
            if !keyboardVisible {
                chromeButton(asset: "HomeBack", identifier: "library.nav.back", label: "Voltar") {
                    dismissKeyboard()
                    mode = .standard
                }
            }
            HomeSearchField(
                text: Binding(get: { store.query }, set: { store.query = $0 }),
                height: Theme.homeNav,
                surfaced: false,
                submit: {
                    search()
                    dismissKeyboard()
                    mode = .standard
                }
            )
            .queepGlass(.capsule)
            .id("library.search.field")
            if keyboardVisible {
                Button(action: dismissKeyboard) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.homePreview)
                        .frame(width: Theme.homeNav, height: Theme.homeNav)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .queepGlass(.circle)
                .accessibilityLabel("Fechar teclado")
                .accessibilityIdentifier("library.search.dismiss")
            }
        }
    }

    private func tab(_ title: String, _ asset: String, _ surface: LibrarySurface, _ identifier: String, flexible: Bool) -> some View {
        let selected = store.surface == surface
        return Button {
            if surface == .home { store.showHome() }
            else { store.surface = surface }
            mode = .standard
        } label: {
            VStack(spacing: 0) {
                HomeGlyph(asset: asset, size: 24, color: selected ? Theme.homeInk : Theme.homePreview)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.homeInk : Theme.homePreview)
            }
            .padding(.horizontal, flexible ? 8 : 18)
            .padding(.vertical, 7)
            .frame(maxWidth: flexible ? .infinity : nil)
            .background {
                if selected {
                    Capsule(style: .continuous).fill(.white.opacity(0.62))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(surface == .spaces ? "Pastas com filtros." : "Galeria")
    }

    private func chromeButton(asset: String, identifier: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HomeGlyph(asset: asset, size: 26)
                .frame(width: Theme.homeNav, height: Theme.homeNav)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .queepGlass(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func addRow(_ title: String, _ asset: String, _ identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            mode = .standard
            action()
        } label: {
            HStack(spacing: 10) {
                HomeGlyph(asset: asset, size: 20)
                Text(title).font(.system(size: 15)).foregroundStyle(Theme.homeInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        keyboardVisible = false
    }
}
#endif
