import QueepCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeTopBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Opaque bar. Reports its height so the library can scroll underneath without a fade.
    func homeTopBar() -> some View {
        background(Theme.surface.ignoresSafeArea(edges: .top))
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: HomeTopBarHeightKey.self, value: geo.size.height)
                }
            }
    }
}

// MARK: - Search

/// Search from the gallery header: the AI search icon, an example query as the hint, and
/// optional tools on the right (screen capture and filters on the Mac).
struct HomeSearchField<Accessories: View>: View {
    @Binding var text: String
    var height: CGFloat = Theme.chrome
    var autofocus = false
    var surfaced = true
    var submit: () -> Void
    @ViewBuilder var accessories: Accessories
    @FocusState private var focused: Bool
    @State private var example = HomeSearchExamples.pick()

    var body: some View {
        HStack(spacing: 16) {
            QueepIcon("ri-search-ai-line", size: 22, color: Theme.ink)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Tente “\(example)”")
                        .font(.system(size: 13))
                        .foregroundStyle(LinearGradient(
                            stops: [
                                .init(color: Theme.inkSoft, location: 0),
                                .init(color: Color(hex: 0xCFCFCF), location: 0.49),
                                .init(color: Color(hex: 0x9C9C9C), location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .accessibilityLabel("Busca da biblioteca")
                    .accessibilityIdentifier("library.search")
            }
            HStack(spacing: 16) { accessories }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .modifier(OptionalSurface(style: .field, radius: Theme.radius, enabled: surfaced))
        .onAppear { if autofocus { focused = true } }
    }
}

extension HomeSearchField where Accessories == EmptyView {
    init(text: Binding<String>, height: CGFloat = Theme.chrome, autofocus: Bool = false,
         surfaced: Bool = true, submit: @escaping () -> Void) {
        self.init(text: text, height: height, autofocus: autofocus, surfaced: surfaced,
                  submit: submit, accessories: { EmptyView() })
    }
}

/// Example queries shown as the search hint. One per appearance.
enum HomeSearchExamples {
    static let all = [
        "CRM colorido para web",
        "landing page escura com 3D",
        "tipografia serifada em pôster",
        "app de finanças minimalista",
        "paleta verde e creme",
        "onboarding com ilustrações",
    ]

    static func pick() -> String { all.randomElement() ?? all[0] }
}

/// The terms of a search, each removable.
struct HomeSearchChips: View {
    let chips: [String]
    var remove: (String) -> Void

    var body: some View {
        HomeChipWrap(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button {
                    remove(chip)
                } label: {
                    HStack(spacing: 6) {
                        Text(chip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        QueepIcon("ri-close-line", size: 14, color: Theme.inkSoft)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .frame(height: 32)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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

// MARK: - Filters, tabs and account

/// Kinds filter. The four coloured dots from the Figma search field.
struct HomeFilterMenu: View {
    @Environment(LibraryStore.self) private var store
    let refresh: () -> Void
    /// Square face behind the dots. Nil draws the dots alone, as inside the search field.
    var chrome: CGFloat? = nil
    var icon: CGFloat = 24

    var body: some View {
        Menu {
            Picker("Tipo", selection: Binding(get: { store.kindFilter ?? "" },
                                              set: { store.kindFilter = $0.isEmpty ? nil : $0 })) {
                Text("Tudo").tag("")
                Text("Notas").tag("note")
                Text("Links").tag("link")
                Text("Imagens").tag("image")
                Text("Áudio e vídeo").tag("media")
            }
            .pickerStyle(.inline)
            Divider()
            Button("Atualizar", action: refresh)
        } label: {
            label
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .accessibilityLabel("Filtrar referências")
        .accessibilityIdentifier("library.filter")
        .help(filterHelp)
    }

    @ViewBuilder private var label: some View {
        let dots = QueepIcon("ri-apps-2-fill", size: icon, original: true)
            .overlay(alignment: .topTrailing) {
                if store.kindFilter != nil {
                    Circle().fill(Theme.forest).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
        if let chrome {
            dots.frame(width: chrome, height: chrome)
                .surface(.fill, radius: chrome >= Theme.chrome ? Theme.radius : Theme.controlRadius)
                .contentShape(Rectangle())
        } else {
            dots.contentShape(Rectangle())
        }
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

/// How many references the account holds, for the Gallery tab. Read from Uso, which counts the
/// whole library; the loaded page would only know the first eighteen.
@MainActor @Observable
final class LibraryTotals {
    static let shared = LibraryTotals()
    private(set) var items: Int?
    private var owner: String?

    func refresh(_ session: Session) async {
        guard let api = session.client(), let uid = session.userID else { return }
        if owner != uid { items = nil; owner = uid }
        guard let usage = try? await api.usage(), session.userID == uid else { return }
        items = usage.counters["items"]?.used
    }
}

/// Gallery and Spaces, each with its count, as in the Figma header.
struct LibraryTabs: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var totals = LibraryTotals.shared
    var stretches = false

    var body: some View {
        QueepSegment<LibrarySurface>(
            items: [
                .init(title: "Gallery", value: LibrarySurface.home, count: galleryCount, identifier: "library.home"),
                .init(title: "Spaces", value: LibrarySurface.spaces,
                      count: store.spaces.isEmpty ? nil : store.spaces.count, identifier: "library.spaces"),
            ],
            selection: Binding(
                get: { store.surface == .spaces ? .spaces : .home },
                set: { surface in
                    if surface == .home { store.showHome() } else { store.show(.spaces) }
                }),
            stretches: stretches)
            .task(id: "\(session.userID ?? "")/\(store.items.count)") {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await totals.refresh(session)
            }
    }

    private var galleryCount: Int? {
        if let items = totals.items { return items }
        return store.hasLoaded && store.surface == .home && store.nextCursor == nil ? store.items.count : nil
    }
}

/// The person, with the plan underneath, as in the Figma header. Opens Ajustes.
struct HomeAccountButton: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var subscriptions = SubscriptionStore.shared
    var size: CGFloat = Theme.chrome

    var body: some View {
        Button {
            store.presentation = .account
        } label: {
            QueepIcon("ri-user-5-fill", size: size * 0.57, color: Theme.ink)
                .frame(width: size, height: size)
                .surface(.fill, radius: size >= Theme.chrome ? Theme.radius : Theme.controlRadius)
                .overlay(alignment: .bottom) {
                    if let plan = subscriptions.access?.plan {
                        PlanBadge(plan: plan)
                            .scaleEffect(size >= Theme.chrome ? 1 : 0.85)
                            .offset(y: size >= Theme.chrome ? 5 : 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Conta e ajustes")
        .accessibilityLabel("Conta")
        .accessibilityValue(subscriptions.access.map { "Plano \($0.plan.title)" } ?? "")
        .accessibilityIdentifier("person.crop.circle")
        .task(id: session.userID) {
            guard session.userID != nil, subscriptions.access == nil else { return }
            await subscriptions.load(session)
        }
    }
}

private struct OptionalSurface: ViewModifier {
    var style: SurfaceStyle
    var radius: CGFloat
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.surface(style, radius: radius) } else { content }
    }
}

// MARK: - Glass

enum QueepGlassShape {
    case circle, capsule, card
}

private struct QueepGlass: ViewModifier {
    var shape: QueepGlassShape = .capsule

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            switch shape {
            case .circle:
                content.glassEffect(.regular.interactive(), in: Circle())
            case .capsule:
                content.glassEffect(.regular, in: Capsule())
            case .card:
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: fallback)
                .overlay(fallback.strokeBorder(Color.white.opacity(0.45)))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
        }
    }

    private var fallback: RoundedRectangle {
        let radius: CGFloat = switch shape {
        case .circle, .capsule: Theme.nav / 2
        case .card: Theme.radius
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// Liquid Glass for iPhone chrome that floats over content: the bottom bar and its menus.
    func queepGlass(_ shape: QueepGlassShape = .capsule) -> some View {
        modifier(QueepGlass(shape: shape))
    }
}

// MARK: - iPhone

#if os(iOS)
enum MobileNavMode: Equatable {
    case standard, add, search
}

/// Top of the iPhone library: the lockup, or the way back from a Space, then filters and account.
struct MobileLibraryHeader: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if store.surface == .spaces, store.selectedSpaceID != nil {
                Button { store.selectSpace(nil) } label: {
                    GalleryPill(title: "Spaces", leading: "ri-arrow-left-s-line", height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spaces")
                .accessibilityIdentifier("spaces.back")
            } else {
                QueepLockup(scale: 0.78)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if session.isLocal {
                QueepIcon("ri-settings-3-line", size: 18, color: Theme.forest)
                    .accessibilityLabel("Versão de desenvolvimento local")
            }
            if store.surface == .spaces, store.selectedSpaceID == nil {
                Button { store.presentation = .newSpace } label: {
                    GalleryPill(title: "Space", leading: "ri-add-line", height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("spaces.new")
            } else {
                HomeFilterMenu(refresh: refresh, chrome: 48, icon: 22)
            }
            HomeAccountButton(size: 48)
        }
        .padding(.horizontal, Theme.navInset)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

struct iPhoneLibrary<Content: View, Dock: View>: View {
    @Environment(LibraryStore.self) private var store
    let search: () -> Void
    let refresh: () async -> Void
    var selecting = false
    @ViewBuilder var content: Content
    @ViewBuilder var dock: Dock
    @State private var mode: MobileNavMode = .standard
    @State private var headerHeight: CGFloat = 72

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                content
                    .padding(.horizontal, Theme.navInset)
                    .padding(.top, max(8, headerHeight + 4))
                    .padding(.bottom, Theme.nav + Theme.navBottom + 24 + (selecting ? 84 : 0))
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity)
            }
            .refreshable { await refresh() }
            .libraryScrollPosition()
            .libraryViewport()
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if selecting {
                    dock
                        .padding(.horizontal, Theme.navInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                MobileLibraryNav(mode: $mode, search: search)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(.spring(duration: 0.28), value: selecting)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                MobileLibraryHeader(refresh: { Task { await refresh() } })
                if kindTitle != nil || !store.searchChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
                        .padding(.horizontal, Theme.navInset)
                    }
                    .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background {
                // White under the status bar and the row, then a short fade into the gallery.
                Theme.surface
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [Theme.surface, Theme.surface.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                            .offset(y: 14)
                    }
                    .ignoresSafeArea(edges: .top)
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: HomeTopBarHeightKey.self, value: geo.size.height)
                }
            }
        }
        .onPreferenceChange(HomeTopBarHeightKey.self) { headerHeight = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.presentation != nil) { _, open in
            if open { mode = .standard }
        }
        .onChange(of: store.requestAddMenu) { _, open in
            guard open else { return }
            store.requestAddMenu = false
            mode = .add
        }
        .overlayPreferenceValue(AddMenuFrameKey.self) { globalFrame in
            if mode == .add {
                AddMenuDismissOverlay(dismiss: { mode = .standard }, globalFrame: globalFrame)
            }
        }
    }

    private func removeChip(_ term: String) {
        store.removeSearchChip(term)
        if !store.searchChips.isEmpty { search() }
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
}

/// Floating bottom bar: Gallery and Spaces, add, search. Glass, because it floats over the gallery.
struct MobileLibraryNav: View {
    @Environment(LibraryStore.self) private var store
    @Binding var mode: MobileNavMode
    let search: () -> Void
    @State private var keyboardVisible = false

    private var navWidth: CGFloat {
        UIScreen.main.bounds.width - Theme.navInset * 2
    }

    private var tabsWidth: CGFloat {
        max(0, navWidth - Theme.nav * 2 - Theme.navGap * 2)
    }

    var body: some View {
        Group {
            if mode == .add {
                addBar
            } else if mode == .search {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: Theme.navGap) { searchBar }
                        .frame(width: navWidth)
                } else {
                    searchBar.frame(width: navWidth, alignment: .leading)
                }
            } else if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: Theme.navGap) { standardBar }
                    .frame(width: navWidth)
            } else {
                standardBar.frame(width: navWidth)
            }
        }
        .frame(width: navWidth)
        .padding(.horizontal, Theme.navInset)
        .padding(.bottom, Theme.navBottom)
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
        HStack(alignment: .bottom, spacing: Theme.navGap) {
            tabGroup(width: tabsWidth)
            chromeButton(asset: "ri-add-line", identifier: "library.add", label: "Queep things") {
                mode = .add
            }
            chromeButton(asset: "ri-search-ai-line", identifier: "library.nav.search", label: "Buscar") {
                mode = .search
            }
        }
        .frame(width: navWidth)
    }

    private var addBar: some View {
        HStack(alignment: .bottom, spacing: Theme.navGap) {
            tabGroup(width: nil)
            addMenu
        }
        .frame(width: navWidth, alignment: .center)
    }

    private func tabGroup(width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            tab("Gallery", .home, "library.home", flexible: width != nil)
            tab("Spaces", .spaces, "library.spaces", flexible: width != nil)
        }
        .padding(Theme.chromeInset)
        .frame(width: width, height: Theme.nav)
        .queepGlass(.capsule)
    }

    private var addMenu: some View {
        // Keeps the card's layout slot. The interactive card is drawn above the dismiss scrim.
        LibraryAddMenu(dismiss: { mode = .standard }, exposesAccessibility: false)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: AddMenuFrameKey.self, value: geo.frame(in: .global))
                }
            }
            .hidden()
    }

    private var searchBar: some View {
        HStack(spacing: Theme.navGap) {
            if !keyboardVisible {
                chromeButton(asset: "ri-arrow-left-s-line", identifier: "library.nav.back", label: "Voltar") {
                    dismissKeyboard()
                    mode = .standard
                }
            }
            HomeSearchField(
                text: Binding(get: { store.query }, set: { store.query = $0 }),
                height: Theme.nav,
                autofocus: true,
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
                    QueepIcon("ri-close-line", size: 22, color: Theme.ink)
                        .frame(width: Theme.nav, height: Theme.nav)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .queepGlass(.circle)
                .accessibilityLabel("Fechar teclado")
                .accessibilityIdentifier("library.search.dismiss")
            }
        }
    }

    private func tab(_ title: String, _ surface: LibrarySurface, _ identifier: String, flexible: Bool) -> some View {
        let selected = store.surface == surface
        return Button {
            if surface == .home { store.showHome() } else { store.show(surface) }
            mode = .standard
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                if surface == .spaces, !store.spaces.isEmpty {
                    CountBadge(value: store.spaces.count, selected: selected)
                }
            }
            .padding(.horizontal, flexible ? 8 : 18)
            .frame(maxWidth: flexible ? .infinity : nil, maxHeight: .infinity)
            .background {
                if selected {
                    Capsule(style: .continuous).fill(.white.opacity(0.7))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chromeButton(asset: String, identifier: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            QueepIcon(asset, size: 26, color: Theme.ink)
                .frame(width: Theme.nav, height: Theme.nav)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .queepGlass(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        keyboardVisible = false
    }
}
#endif

// MARK: - Queep things

private struct AddMenuCardShape: Shape {
    var rect: CGRect
    func path(in _: CGRect) -> Path { Path(rect) }
}

private struct AddMenuFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

/// Full-screen hit target behind the Queep things card. Taps outside the card dismiss the menu
/// and are not delivered to the gallery, the top bar, or the tabs.
private struct AddMenuDismissOverlay: View {
    var dismiss: () -> Void
    var globalFrame: CGRect

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let x = globalFrame.minX - origin.x
            let y = globalFrame.minY - origin.y
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                    .accessibilityLabel("Fechar")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("library.add.dismiss")
                    .accessibilitySortPriority(-1)
                if globalFrame.width > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: max(0, y))
                            .allowsHitTesting(false)
                        HStack(alignment: .top, spacing: 0) {
                            Color.clear
                                .frame(width: max(0, x))
                                .allowsHitTesting(false)
                            LibraryAddMenu(dismiss: dismiss)
                                .accessibilitySortPriority(1)
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(AddMenuCardShape(rect: CGRect(x: x, y: y, width: globalFrame.width, height: globalFrame.height)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

/// What Queep things can save. Glass on the iPhone bar; a white card under the Mac header.
private struct LibraryAddMenu: View {
    @Environment(LibraryStore.self) private var store
    var dismiss: () -> Void
    var exposesAccessibility = true

    var body: some View {
        VStack(spacing: 2) {
            addRow("Posts", "ri-hashtag", "library.add.post") {
                store.startCapture(kind: "link", intent: "post")
            }
            addRow("Galeria", "ri-image-line", "library.add.files") {
                DispatchQueue.main.async { store.openPhotoLibrary = true }
            }
            #if os(macOS)
            addRow("Arquivos", "ri-folder-line", "library.add.arquivo") {
                DispatchQueue.main.async { store.openFileImporter = true }
            }
            #endif
            addRow("Sites", "ri-link", "library.add.site") {
                store.startCapture(kind: "link", intent: "site")
            }
            addRow("Notes", "ri-sticky-note-line", "library.add.note") {
                store.startCapture(kind: "note")
            }
        }
        .padding(Theme.chromeInset)
        .frame(width: 232)
        .modifier(AddMenuSurface())
        .accessibilityHidden(!exposesAccessibility)
    }

    private func addRow(_ title: String, _ asset: String, _ identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 12) {
                IconTile(asset: asset, size: 40, icon: 18)
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(AddRowStyle())
        .accessibilityIdentifier(exposesAccessibility ? identifier : "")
        .accessibilityLabel(title)
        .accessibilityHidden(!exposesAccessibility)
    }
}

private struct AddRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AddRowBody(configuration: configuration)
    }
}

private struct AddRowBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .background {
                if hovered || configuration.isPressed {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.fill.opacity(0.7))
                }
            }
            .onHover { hovered = $0 }
    }
}

private struct AddMenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.queepGlass(.card)
        #else
        content
            .surface(.outline, radius: Theme.radius)
            .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
        #endif
    }
}

/// Mac header control. Opens the Queep things card under it.
struct QueepThingsControl: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                QueepIcon("ri-add-line", size: 24, color: Theme.ink)
                Text("Queep things")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.control)
            .background {
                if isPresented {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Color.white.opacity(0.7))
                }
            }
            .chrome(.fill)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.add")
        .accessibilityLabel("Queep things")
        .help("Posts, galeria, arquivos, sites ou notes")
        .overlay(alignment: .topTrailing) {
            if isPresented {
                LibraryAddMenu(dismiss: { isPresented = false }, exposesAccessibility: false)
                    .fixedSize()
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: AddMenuFrameKey.self, value: geo.frame(in: .global))
                        }
                    }
                    .opacity(0)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .offset(y: Theme.chrome + 8)
            }
        }
    }
}

extension View {
    /// Card anchored to Queep things. Taps outside the card dismiss it.
    func queepThingsMenu(isPresented: Binding<Bool>) -> some View {
        overlayPreferenceValue(AddMenuFrameKey.self) { frame in
            if isPresented.wrappedValue {
                AddMenuDismissOverlay(dismiss: { isPresented.wrappedValue = false }, globalFrame: frame)
            }
        }
        .animation(.spring(duration: 0.22, bounce: 0), value: isPresented.wrappedValue)
    }
}
