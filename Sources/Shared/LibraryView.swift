import SwiftUI
import PhotosUI
import QueepCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct LibraryView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var logoutError: String?
    @State private var actionError: String?
    @State private var pendingDelete: Reference?
    @State private var pendingSelectionDelete: [Reference] = []
    @State private var macHeaderHeight: CGFloat = 140
    @State private var libraryViewport = CGRect.null
    @State private var libraryScroll = LibraryScrollLive()
    @State private var libraryScrollTick = 0
    #if os(macOS)
    @State private var macAddOpen = false
    /// The plane, the dated gallery or the list, picked under the bar and remembered.
    @AppStorage("queep.libraryLayout") private var libraryLayout = LibraryLayout.infinite
    #endif
    /// Anything selected puts the gallery in selection mode; clearing it leaves.
    @State private var selectedIDs: Set<String> = []
    @State private var spaceSelection: [Reference] = []
    @State private var pickingSpaces = false
    @State private var subscriptions = SubscriptionStore.shared
    @AppStorage("queep.firstSearchHint.dismissed") private var searchHintDismissed = false
    @State private var onboardingPresented = false
    @State private var onboardingDismissed = false
    @State private var sawEmptyLibrary = false
    @State private var conversionOffer: PaywallContext?
    @State private var consideringFirstPaywall = false
    @State private var galleryPhoto: PhotosPickerItem?
    @State private var sendingPhoto = false
    @State private var sendingMessage = "Enviando imagem…"

    private var filtered: [Reference] {
        let items = store.searchItems ?? store.items
        guard let kind = store.kindFilter else { return items }
        if kind == "media" { return items.filter { $0.kind == "audio" || $0.kind == "video" } }
        return items.filter { $0.kind == kind }
    }
    private var searching: Bool { store.searchItems != nil }
    private var selecting: Bool { !selectedIDs.isEmpty }
    /// Selection works on the gallery itself, not on the Spaces overview.
    private var canSelect: Bool {
        !store.items.isEmpty && !searching && !(store.surface == .spaces && store.selectedSpaceID == nil)
    }
    /// Free accounts see the PRO tile first in the gallery. Not in search, Spaces or Arquivados.
    private var showsPromoTile: Bool {
        subscriptions.access?.plan == .free && subscriptions.access?.isDevelopment == false
            && store.surface == .home && !searching && store.kindFilter == nil
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            libraryStack
            .subscriptionGate(enabled: store.presentation == nil)
            .sheet(item: sheetPresentation) { presentation in
                switch presentation {
                case .account: AccountView()
                case .usage: UsagePrivacyView()
                case .help: HelpView()
                case .deleteAccount: DeleteAccountView()
                case .subscription: SubscriptionView(managesOnly: true)
                case .newSpace: SpaceNameSheet()
                case .capture:
                    if store.captureKind == "link" && (store.captureIntent == "post" || store.captureIntent == "site") {
                        LinkCaptureView()
                    } else {
                        CaptureView(reference: nil, initialKind: store.captureKind)
                    }
                case .reference(let reference):
                    GalleryDetailView(reference: reference, items: galleryItems) { store.presentation = nil }
                        #if os(iOS)
                        .presentationDragIndicator(.hidden)
                        #endif
                }
            }
            .alert("Não foi possível sair", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK") { logoutError = nil }
            } message: { Text(logoutError ?? "") }
            .alert("Não foi possível concluir", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: { Text(actionError ?? "") }
            .photosPicker(isPresented: $store.openPhotoLibrary, selection: $galleryPhoto,
                          matching: .images, preferredItemEncoding: .current)
            #if os(macOS)
            .fileImporter(isPresented: $store.openFileImporter, allowedContentTypes: [.image, .movie, .audio]) { result in
                Task { await sendImportedFile(result) }
            }
            #endif
            .onChange(of: galleryPhoto) { _, item in
                guard let item else { return }
                galleryPhoto = nil
                Task { await sendGalleryPhoto(item) }
            }
            .confirmationDialog("Excluir permanentemente esta referência?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { reference in
                Button("Excluir \(reference.kindLabel.lowercased())", role: .destructive) { Task { await remove(reference) } }
            } message: { reference in
                Text("Arquivar esconde. Excluir apaga da sua conta.\n\n\(reference.displayTitle)")
            }
            .confirmationDialog(pendingSelectionDelete.count <= 1
                                ? "Excluir permanentemente esta referência?"
                                : "Excluir permanentemente estas \(pendingSelectionDelete.count) referências?",
                                isPresented: Binding(get: { !pendingSelectionDelete.isEmpty },
                                                     set: { if !$0 { pendingSelectionDelete = [] } }),
                                titleVisibility: .visible,
                                presenting: pendingSelectionDelete.isEmpty ? nil : pendingSelectionDelete) { references in
                Button(references.count == 1
                       ? "Excluir \(references[0].kindLabel.lowercased())"
                       : "Excluir \(references.count)", role: .destructive) {
                    pendingSelectionDelete = []
                    selectedIDs = []
                    Task { await remove(references) }
                }
            } message: { references in
                if references.count == 1 {
                    Text("Arquivar esconde. Excluir apaga da sua conta.\n\n\(references[0].displayTitle)")
                } else {
                    Text("Arquivar esconde. Excluir apaga da sua conta.")
                }
            }
        }
        .overlay(alignment: .bottom) { archiveToast }
        .sheet(isPresented: $pickingSpaces) { SpacePicker(references: spaceSelection) }
        .onChange(of: store.presentation?.id) { _, _ in
            if case .reference(let reference) = store.presentation {
                ProductAnalytics.referenceOpened(kind: reference.kind, url: reference.url)
            }
        }
        .onChange(of: store.selectedSpaceID) { _, _ in
            selectedIDs = []
            Task {
                await refresh(force: false)
                if !store.searchChips.isEmpty { await search() }
            }
        }
        .onChange(of: store.surface) { _, _ in
            selectedIDs = []
            Task { await refresh(force: false) }
        }
        .onChange(of: searching) { _, now in
            if now { selectedIDs = [] }
        }
        .onAppear {
            noteEmptyLibrary()
            presentOnboardingIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-paywall") {
                conversionOffer = PaywallContext(reason: "preview")
            }
            FeedNotice.scheduleAfterLibraryAppears(
                isLocal: session.isLocal,
                access: SubscriptionStore.shared.access)
            #endif
        }
        .onChange(of: store.hasLoaded) { _, _ in
            noteEmptyLibrary()
            presentOnboardingIfNeeded()
        }
        .onChange(of: store.items.count) { _, _ in
            noteEmptyLibrary()
            considerFirstPaywall()
            // Drop what left the library (archived, deleted or moved by another device).
            let present = Set(filtered.map(\.id))
            if !selectedIDs.isSubset(of: present) { selectedIDs.formIntersection(present) }
        }
        .onChange(of: onboardingPresented) { _, _ in considerFirstPaywall() }
        .onChange(of: store.paywallReason) { _, reason in
            guard let reason else { return }
            store.paywallReason = nil
            // Let the Ajustes sheet finish closing before the card appears.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                conversionOffer = PaywallContext(reason: reason)
            }
        }
        .modifier(OnboardingCover(isPresented: $onboardingPresented) {
            OnboardingFlow {
                onboardingDismissed = true
                onboardingPresented = false
            }
        })
        .journeyPaywall($conversionOffer)
        .task(id: session.userID) { await restoreOnboarding() }
        .onPreferenceChange(LibraryViewportKey.self) { frame in
            guard frame.width > 1, frame.height > 1 else { return }
            guard abs(frame.minX - libraryViewport.minX) > 0.5
                    || abs(frame.minY - libraryViewport.minY) > 0.5
                    || abs(frame.width - libraryViewport.width) > 0.5
                    || abs(frame.height - libraryViewport.height) > 0.5 else { return }
            libraryViewport = frame
        }
    }

    private var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    private func presentOnboardingIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-paywall") { return }
        #endif
        guard !onboardingPresented, !onboardingDismissed, !uiTesting, let uid = session.userID else { return }
        guard !OnboardingProgress.isComplete(uid) else { return }
        guard store.hasLoaded, store.items.isEmpty, store.error == nil, !searching else { return }
        onboardingPresented = true
    }

    private func noteEmptyLibrary() {
        if store.hasLoaded && store.items.isEmpty && store.error == nil { sawEmptyLibrary = true }
    }

    private func considerFirstPaywall() {
        guard !uiTesting, sawEmptyLibrary, !store.items.isEmpty, !onboardingPresented else { return }
        guard let uid = session.userID, !OnboardingProgress.paywallShown(uid), conversionOffer == nil else { return }
        guard !consideringFirstPaywall else { return }
        consideringFirstPaywall = true
        Task {
            defer { consideringFirstPaywall = false }
            await SubscriptionStore.shared.load(session)
            guard session.userID == uid, conversionOffer == nil, !OnboardingProgress.paywallShown(uid) else { return }
            let subscription = SubscriptionStore.shared
            let decision = FirstPaywall.decide(
                offersLoaded: subscription.storeAvailable && !subscription.packages.isEmpty,
                access: subscription.access)
            guard decision.rememberShown else { return }
            OnboardingProgress.markPaywallShown(uid)
            if decision == .show { conversionOffer = PaywallContext(reason: "first_save") }
        }
    }

    private func restoreOnboarding() async {
        guard let uid = session.userID, let api = session.client(), !OnboardingProgress.isComplete(uid) else { return }
        if let _ = try? await api.onboardingProfile() {
            OnboardingProgress.markComplete(uid)
            onboardingDismissed = true
        }
    }

    @ViewBuilder private var libraryStack: some View {
        #if os(macOS)
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if usesInfiniteGallery {
                    InfiniteBentoGallery(items: filtered, endless: canvasIsEndless,
                                         topInset: macHeaderHeight + geo.safeAreaInsets.top + (showsCanvasHeading ? 64 : 56),
                                         more: !searching && store.nextCursor != nil,
                                         loading: store.loadingMore || store.loading,
                                         showsPromo: showsPromoTile,
                                         selecting: selecting, selectedIDs: selectedIDs,
                                         open: { open($0) }, toggle: galleryToggle,
                                         promo: { conversionOffer = PaywallContext(reason: "gallery_tile") },
                                         loadMore: loadMorePage,
                                         menu: { cardMenu($0) })
                        .id(canvasID)
                        .ignoresSafeArea(.container, edges: .top)
                    canvasHeading
                        .padding(.horizontal, Theme.pageMargin(for: geo.size.width))
                        .padding(.top, macHeaderHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if usesTable {
                    LibraryTable(items: filtered, more: !searching && store.nextCursor != nil,
                                 loading: store.loadingMore || store.loading,
                                 selection: $selectedIDs, open: { open($0) }, loadMore: loadMorePage,
                                 menu: { cardMenu($0) })
                        .padding(.horizontal, Theme.pageMargin(for: geo.size.width) - 8)
                        .padding(.top, macHeaderHeight + (showsCanvasHeading ? 52 : 48))
                        .padding(.bottom, selecting ? 80 : 0)
                    canvasHeading
                        .padding(.horizontal, Theme.pageMargin(for: geo.size.width))
                        .padding(.top, macHeaderHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                ScrollView {
                    libraryContents
                        .padding(.horizontal, Theme.pageMargin(for: geo.size.width))
                        .padding(.bottom, 40 + (selecting ? 92 : 0))
                        .padding(.top, max(8, macHeaderHeight + geo.safeAreaInsets.top + (showsLayoutSwitch ? 48 : 0)))
                        .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
                .modifier(MacScrollGeometryPublisher(live: libraryScroll) {
                    libraryScrollTick += 1
                })
                .libraryScrollPosition()
                .libraryViewport()
                }
                MacLibraryHeader(
                    search: { Task { await search() } },
                    refresh: { Task { await refresh(force: true) } },
                    addOpen: $macAddOpen
                )
                .homeFloatingBar()
                .onPreferenceChange(HomeTopBarHeightKey.self) { macHeaderHeight = $0 }
                if showsLayoutSwitch {
                    LibraryLayoutSwitch(layout: $libraryLayout)
                        .padding(.top, macHeaderHeight)
                        .padding(.trailing, Theme.pageMargin(for: geo.size.width))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .queepThingsMenu(isPresented: $macAddOpen)
        .onChange(of: store.requestAddMenu) { _, open in
            guard open else { return }
            store.requestAddMenu = false
            macAddOpen = true
        }
        .overlay(alignment: .bottom) {
            if selecting {
                selectionDock
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay { macGallery }
        .animation(.spring(duration: 0.28), value: selecting)
        .animation(.easeOut(duration: 0.15), value: macGalleryID)
        .background(Theme.surface)
        .preferredColorScheme(.light)
        .hideMacWindowTitle()
        #else
        iPhoneLibrary(
            search: { Task { await search() } },
            refresh: { await refresh(force: true) },
            selecting: selecting,
            content: { libraryContents },
            dock: { if selecting { selectionDock } }
        )
        .background(Theme.surface)
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: selectedIDs)
        #endif
    }

    private var libraryContents: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(macOS)
            if session.isLocal {
                Label("Versão de desenvolvimento local", systemImage: "hammer")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
            }
            #endif
            if store.surface == .spaces, store.selectedSpaceID == nil {
                SpacesOverview()
            } else {
            #if os(macOS)
            if store.surface == .spaces, store.selectedSpaceID != nil {
                Button { store.selectSpace(nil) } label: {
                    GalleryPill(title: "Spaces", leading: "ri-arrow-left-s-line")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spaces")
                .accessibilityIdentifier("spaces.back")
            }
            #endif
            if store.surface == .spaces, let space = store.selectedSpace {
                PageTitle(text: space.name, detail: space.countLabel)
            }
            if store.surface == .archived {
                HStack(alignment: .center, spacing: 12) {
                    PageTitle(text: "Arquivados")
                    Spacer(minLength: 12)
                    Button { store.showHome() } label: {
                        GalleryPill(title: "Gallery", leading: "ri-arrow-left-s-line")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.archived.back")
                }
            }
            if sendingPhoto {
                LibraryBanner(icon: "ri-loader-4-line", text: sendingMessage)
                    .accessibilityIdentifier("library.sendingPhoto")
            }
            if let error = store.error {
                LibraryBanner(icon: "ri-wifi-off-line", text: error) {
                    Button("Tentar novamente") { Task { await refresh(force: true) } }
                        .buttonStyle(.queep(.neutral, height: 36, stretches: false))
                }
            }
            if store.surface == .home && store.items.count == 1 && !searching && !searchHintDismissed && conversionOffer == nil {
                LibraryBanner(icon: "ri-search-ai-line",
                              text: "Referência salva. Busque pelo nome ou, depois da análise, pelo assunto e pela aparência.") {
                    Button { searchHintDismissed = true } label: {
                        QueepIcon("ri-close-line", size: 20, color: Theme.inkSoft)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dispensar dica de busca")
                    .accessibilityIdentifier("onboarding.dismissHint")
                }
                .accessibilityIdentifier("onboarding.searchHint")
            }
            if SearchPresentation.showsPending(hasPending: store.hasPending, showingSearch: searching) {
                HStack(spacing: 8) {
                    QueepIcon("ri-time-line", size: 16, color: Theme.inkSoft)
                    Text(SearchPresentation.pending)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("search.pending")
            }
            if store.searching {
                GallerySkeleton()
                    .accessibilityLabel("Buscando nas suas referências")
            } else if let searchError = store.searchError {
                EmptyState(icon: "ri-search-line", title: SearchPresentation.failureMessage(searchError),
                           message: "Suas referências continuam salvas.")
            } else if store.items.isEmpty && store.loading && !store.hasLoaded {
                GallerySkeleton()
                    .accessibilityLabel("Carregando suas referências")
            } else if store.items.isEmpty && store.error != nil && !searching {
                EmptyState(icon: "ri-wifi-off-line", title: "Não foi possível carregar a biblioteca",
                           message: "Toque em Tentar novamente para recuperar suas referências.")
            } else if store.items.isEmpty && !searching && store.error == nil {
                if store.surface == .archived {
                    EmptyState(icon: "ri-archive-line", title: "Nenhum item arquivado",
                               message: "Itens arquivados saem da Gallery e continuam guardados aqui.")
                } else if store.surface == .spaces && store.selectedSpaceID != nil {
                    EmptySpaceView()
                } else if store.surface == .home && store.hasArchivedItems {
                    EmptyState(icon: "ri-archive-line", title: "Tudo arquivado",
                               message: "Sua Gallery está vazia. Em Ajustes, abra Arquivados para restaurar itens.")
                } else {
                    FirstUseView(scrolls: false)
                }
            } else if filtered.isEmpty {
                EmptyState(icon: searching ? "ri-search-eye-line" : "ri-bookmark-line",
                           title: emptyFilterTitle, message: emptyFilterMessage) {
                    if !searching {
                        Button("Adicionar referência") { store.requestAddMenu = true }
                            .buttonStyle(.queep(.primary, stretches: false))
                            .accessibilityIdentifier("library.add.reference")
                    }
                }
            } else {
                #if os(macOS)
                if libraryLayout == .grouped {
                    DateGroupedGallery(items: filtered, more: !searching && store.nextCursor != nil,
                                       loading: store.loadingMore || store.loading,
                                       selecting: selecting, selectedIDs: selectedIDs,
                                       open: { open($0) }, toggle: galleryToggle, loadMore: loadMorePage,
                                       menu: { cardMenu($0) }) {
                        if showsPromoTile {
                            PromoTile { conversionOffer = PaywallContext(reason: "gallery_tile") }
                        }
                    }
                } else {
                    scrollingGallery
                }
                #else
                scrollingGallery
                #endif
            }
            }
        }
    }

    private var scrollingGallery: some View {
                LibraryGallery(items: filtered, more: !searching && store.nextCursor != nil,
                               loading: store.loadingMore,
                               busy: store.loading || store.loadingMore || store.refreshing,
                               failed: store.error != nil,
                               viewport: galleryLoopViewport,
                               selecting: selecting, selectedIDs: selectedIDs,
                               resetID: "\(store.filterKey)|\(store.kindFilter ?? "")|\(searching)",
                               scrollLive: libraryScroll,
                               scrollTick: libraryScrollTick,
                               onScrollPage: { libraryScrollTick += 1 },
                               open: { open($0) },
                               toggle: galleryToggle,
                               brush: { id, include in
                                   if include {
                                       if selectedIDs.count < 50 { selectedIDs.insert(id) }
                                   } else {
                                       selectedIDs.remove(id)
                                   }
                               },
                               loadMore: loadMorePage, menu: { cardMenu($0) }, leading: {
                    if showsPromoTile {
                        PromoTile { conversionOffer = PaywallContext(reason: "gallery_tile") }
                    }
                })
    }

    /// Nil where the gallery cannot select, so the tiles hide the mark and ignore the long press.
    #if os(macOS)
    /// Home only: Spaces and Arquivados keep their headings in the scrolling gallery.
    /// The plane lays out home, search, a Space and Arquivados when it is the chosen layout.
    private var usesInfiniteGallery: Bool {
        libraryLayout == .infinite && showsLayoutSwitch
    }

    private var usesTable: Bool {
        libraryLayout == .list && showsLayoutSwitch
    }

    /// The switch shows wherever there are references to lay out: not on the Spaces overview,
    /// an empty collection or an error.
    private var showsLayoutSwitch: Bool {
        store.error == nil && store.searchError == nil && !filtered.isEmpty
            && !(store.surface == .spaces && store.selectedSpaceID == nil)
    }

    /// New results, filter or collection start from the middle of a fresh plane.
    private var canvasID: String {
        "\(store.filterKey)|\(store.kindFilter ?? "")|\(store.searchChips.joined(separator: ","))|\(searching)"
    }

    /// Only a large collection repeats. Search never does: copies of a result read as duplicates.
    /// The total comes from the account counters or the Space; without one, more pages to load
    /// means the collection is large.
    private var canvasIsEndless: Bool {
        guard !searching else { return false }
        let total: Int? = switch store.surface {
        case .home: store.kindFilter == nil ? LibraryTotals.shared.items : nil
        case .spaces: store.selectedSpace?.referenceCount
        default: nil
        }
        let known = total ?? (store.nextCursor != nil ? Int.max : filtered.count)
        return known >= InfiniteBentoPlan.endlessMinimum
    }

    private var showsCanvasHeading: Bool {
        (store.surface == .spaces && store.selectedSpace != nil) || store.surface == .archived || store.searching
    }

    /// What the scrolling page shows above its gallery, floating under the bar on the plane.
    @ViewBuilder private var canvasHeading: some View {
        let space = store.surface == .spaces ? store.selectedSpace : nil
        if showsCanvasHeading {
            HStack(alignment: .center, spacing: 12) {
                if let space {
                    Button { store.selectSpace(nil) } label: {
                        GalleryPill(title: "Spaces", leading: "ri-arrow-left-s-line")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Spaces")
                    .accessibilityIdentifier("spaces.back")
                    Text(space.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(space.countLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.trailing, 8)
                } else if store.surface == .archived {
                    Button { store.showHome() } label: {
                        GalleryPill(title: "Gallery", leading: "ri-arrow-left-s-line")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.archived.back")
                    Text("Arquivados")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.trailing, 8)
                }
                if store.searching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Buscando…").font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 10)
                    .accessibilityIdentifier("library.searching")
                }
            }
            .padding(6)
            .floatingSurface(radius: 22)
        }
    }
    #endif

    private func loadMorePage() {
        Task {
            guard let api = session.client(), let uid = session.userID else { return }
            await store.refresh(api, account: uid, more: true)
        }
    }

    private var galleryToggle: ((Reference) -> Void)? {
        guard canSelect else { return nil }
        return { toggle($0) }
    }

    private var emptyFilterTitle: String {
        if searching { return "Nada parecido por aqui" }
        return store.kindFilter == nil ? "Seu espaço para lembrar" : "Nada neste filtro"
    }

    private var emptyFilterMessage: String {
        if searching {
            return SearchPresentation.emptyDescription(
                archived: store.surface == .archived,
                localFilterHidMatches: store.kindFilter != nil && store.searchItems?.isEmpty == false)
        }
        return store.kindFilter == nil
            ? "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos."
            : "Esse tipo ainda não está na biblioteca. Queep things guarda o próximo."
    }

    /// Right-click on the Mac: the basics without opening the item.
    @ViewBuilder private func cardMenu(_ reference: Reference) -> some View {
        Button("Abrir", systemImage: "arrow.up.right.square") { store.presentation = .reference(reference) }
        if canSelect {
            Button(selectedIDs.contains(reference.id) ? "Desmarcar" : "Selecionar",
                   systemImage: "checkmark.circle") { toggle(reference) }
        }
        Button("Space", systemImage: "square.stack.3d.up") {
            spaceSelection = [reference]
            pickingSpaces = true
        }
        if let url = reference.url { Button("Copiar link", systemImage: "link") { Clipboard.copy(url) } }
        if !reference.text.isEmpty { Button("Copiar texto", systemImage: "doc.on.doc") { Clipboard.copy(reference.text) } }
        Divider()
        Button(reference.isArchived ? "Desarquivar" : "Arquivar",
               systemImage: reference.isArchived ? "archivebox.fill" : "archivebox") {
            archive([reference], archived: !reference.isArchived)
        }
        Button("Excluir…", systemImage: "trash", role: .destructive) { pendingDelete = reference }
    }

    private var selectionCountLabel: String {
        "\(selectedIDs.count) selecionado\(selectedIDs.count == 1 ? "" : "s")"
    }

    /// Floating bar while anything is selected: how many, Spaces, archive, delete, and a way out.
    /// The Mac's floating chrome is compact; the iPhone keeps the Figma's 46pt controls.
    private var dockMetrics: ChromeMetrics {
        #if os(macOS)
        .compact
        #else
        .regular
        #endif
    }

    private var selectionDock: some View {
        HStack(spacing: 8) {
            Button { selectedIDs = [] } label: {
                QueepIcon("ri-close-line", size: dockMetrics.icon, color: Theme.ink)
                    .frame(width: dockMetrics.control, height: dockMetrics.control)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: dockMetrics.controlRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Limpar seleção · Esc")
            .accessibilityLabel("Limpar seleção")
            .accessibilityIdentifier("library.select")
            Text(selectionCountLabel)
                .font(.system(size: dockMetrics.bare ? 14 : 15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
                #if os(iOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            #if os(macOS)
            Spacer(minLength: 24)
            #endif
            dockButton("Spaces", icon: "ri-folder-add-line", identifier: "library.spaceSelection",
                       action: assignSelectionToSpaces)
            dockButton(store.surface == .archived ? "Desarquivar" : "Arquivar",
                       icon: store.surface == .archived ? "ri-inbox-unarchive-line" : "ri-archive-line",
                       identifier: "library.archiveSelection", action: archiveSelection)
            dockButton("Excluir", icon: "ri-delete-bin-line", identifier: "library.deleteSelection",
                       destructive: true, action: deleteSelection)
        }
        .padding(dockMetrics.inset)
        #if os(macOS)
        .floatingSurface(radius: dockMetrics.containerRadius)
        #else
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line)
        }
        .shadow(color: .black.opacity(0.10), radius: 24, y: 10)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selectionCountLabel)
    }

    private func dockButton(_ title: String, icon: String, identifier: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            #if os(macOS)
            HStack(spacing: 6) {
                QueepIcon(icon, size: 18, color: destructive ? Theme.danger : Theme.ink)
                Text(title).font(.system(size: 14))
            }
            #else
            QueepIcon(icon, size: 22, color: destructive ? Theme.danger : Theme.ink)
            #endif
        }
        #if os(macOS)
        .buttonStyle(.queep(destructive ? .destructive : .neutral, height: dockMetrics.control, stretches: false,
                            radius: dockMetrics.controlRadius))
        #else
        .buttonStyle(.queep(destructive ? .destructive : .neutral, height: Theme.control, stretches: false))
        .frame(width: Theme.control + 8)
        #endif
        .disabled(selectedIDs.isEmpty)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func toggle(_ reference: Reference) {
        if selectedIDs.contains(reference.id) {
            selectedIDs.remove(reference.id)
        } else if selectedIDs.count < 50 {
            selectedIDs.insert(reference.id)
        }
    }

    private func assignSelectionToSpaces() {
        spaceSelection = filtered.filter { selectedIDs.contains($0.id) }
        pickingSpaces = !spaceSelection.isEmpty
    }

    private func archiveSelection() {
        let chosen = filtered.filter { selectedIDs.contains($0.id) }
        archive(chosen, archived: store.surface != .archived)
        selectedIDs = []
    }

    private func deleteSelection() {
        pendingSelectionDelete = filtered.filter { selectedIDs.contains($0.id) }
    }

    private var galleryItems: [Reference] { filtered }

    /// Grid loops stop while an item is open so the focused slide is the one that plays.
    private var galleryLoopViewport: CGRect {
        if case .reference = store.presentation { return .null }
        return libraryViewport
    }

    /// On the Mac the opened picture covers the library like saved.design; everything else is a sheet.
    private var sheetPresentation: Binding<LibraryPresentation?> {
        Binding(get: {
            #if os(macOS)
            if case .reference = store.presentation { return nil }
            #endif
            return store.presentation
        }, set: { store.presentation = $0 })
    }

    #if os(macOS)
    private var macGalleryID: String? {
        if case .reference(let reference) = store.presentation { return reference.id }
        return nil
    }

    @ViewBuilder private var macGallery: some View {
        if case .reference(let reference) = store.presentation {
            GalleryDetailView(reference: reference, items: galleryItems) { store.presentation = nil }
                .transition(.opacity)
        }
    }
    #endif

    @ViewBuilder private var archiveToast: some View {
        if let undo = store.archiveUndo {
            HStack(spacing: 14) {
                QueepIcon("ri-archive-line", size: 20, color: Theme.onAction)
                Text(undo.references.count == 1 ? "Arquivado" : "\(undo.references.count) arquivados")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.onAction)
                Button("Desfazer") {
                    guard let api = session.client(), let uid = session.userID else { return }
                    store.undoArchive(undo, client: api, account: uid)
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.lime)
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.control)
            .background(Theme.action, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.bottom, selecting ? 110 : 28)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Arquivado")
            .task(id: undo.id) {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                if store.archiveUndo?.id == undo.id { store.archiveUndo = nil }
            }
        }
    }

    private func open(_ reference: Reference) {
        if selecting {
            toggle(reference)
        } else {
            store.presentation = .reference(reference)
        }
    }

    private func archive(_ references: [Reference], archived: Bool) {
        guard let api = session.client(), let uid = session.userID, !references.isEmpty else { return }
        store.setArchived(references, archived: archived, client: api, account: uid)
    }

    private func remove(_ reference: Reference) async {
        await remove([reference])
    }

    private func remove(_ references: [Reference]) async {
        guard let api = session.client(), let uid = session.userID, !references.isEmpty else { return }
        var failure: String?
        for reference in references {
            do {
                try await api.delete(reference)
                guard session.userID == uid else { return }
                store.discardSearchReference(reference.id)
            } catch {
                failure = error.localizedDescription
            }
        }
        guard session.userID == uid else { return }
        await store.refresh(api, account: uid, force: true)
        if let failure { actionError = failure }
    }

    private func refresh(force: Bool) async {
        guard let api = session.client(), let uid = session.userID else { return }
        await store.refresh(api, account: uid, force: force)
    }

    private func search() async {
        guard let api = session.client(), let uid = session.userID else { return }
        await store.search(api, account: uid)
    }

    private func sendGalleryPhoto(_ selection: PhotosPickerItem) async {
        guard !sendingPhoto else { return }
        sendingPhoto = true
        sendingMessage = "Enviando imagem…"
        actionError = nil
        defer { sendingPhoto = false }
        do {
            guard let image = try await selection.loadTransferable(type: ImportedImage.self) else {
                throw QueepError.server("Não foi possível abrir esta foto.")
            }
            guard let api = session.client(), let uid = session.userID else { return }
            let saved = try await api.uploadImage(id: UUID(), title: "", data: image.data)
            ProductAnalytics.captureSaved(kind: saved.kind, url: saved.url, source: "library")
            guard session.userID == uid else { return }
            await store.refresh(api, account: uid, force: true)
        } catch is CancellationError {
        } catch let failure as QueepError {
            if case .planRequired = failure { return }
            actionError = failure.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }

    #if os(macOS)
    private func sendImportedFile(_ result: Result<URL, Error>) async {
        guard !sendingPhoto else { return }
        sendingPhoto = true
        sendingMessage = "Enviando arquivo…"
        actionError = nil
        defer { sendingPhoto = false }
        do {
            let url = try result.get()
            guard let api = session.client(), let uid = session.userID else { return }
            let saved: Reference
            switch importedKind(url) {
            case .image:
                let image = try ImportedImage.prepare(url: url)
                saved = try await api.uploadImage(id: UUID(), title: "", data: image.data)
            case .media:
                try await api.requireMediaAccess()
                let media = try await ImportedMedia.prepare(url: url)
                saved = try await api.uploadMedia(id: UUID(), title: "", file: media.file.url)
            case .other:
                throw QueepError.server("Escolha uma imagem, um áudio ou um vídeo.")
            }
            ProductAnalytics.captureSaved(kind: saved.kind, url: saved.url, source: "library")
            guard session.userID == uid else { return }
            await store.refresh(api, account: uid, force: true)
        } catch is CancellationError {
        } catch let failure as QueepError {
            if case .planRequired = failure { return }
            actionError = failure.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }

    private enum ImportedKind { case image, media, other }

    private func importedKind(_ url: URL) -> ImportedKind {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio) { return .media }
        if type.conforms(to: .image) { return .image }
        return .other
    }
    #endif
}

/// Loading gallery from the Figma: pale tiles in the masonry, breathing while the page arrives.
struct GallerySkeleton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [340, 290, 147, 340, 232, 340, 340, 230, 415, 340, 147, 340]

    var body: some View {
        MasonryLayout(spacing: Theme.gap, forceColumns: typeSize.isAccessibilitySize ? 1 : nil) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.fill)
                    .frame(height: height * scale)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.55]) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in .easeInOut(duration: 1.1).delay(Double(index % 5) * 0.08) }
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private var scale: CGFloat {
        #if os(iOS)
        return 0.62
        #else
        return 1
        #endif
    }
}

/// A notice above the gallery: icon, text, and an optional action on the right.
struct LibraryBanner<Accessory: View>: View {
    let icon: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            IconTile(asset: icon, size: 36, icon: 18, fill: Theme.surface)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(Theme.chromeInset + 4)
        .surface(.fill, radius: Theme.radius)
    }
}

extension LibraryBanner where Accessory == EmptyView {
    init(icon: String, text: String) {
        self.init(icon: icon, text: text, accessory: { EmptyView() })
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
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Masonry with saved.design's breakpoints: two columns on the phone, up to five on a wide window.
struct MasonryLayout: Layout {
    var spacing: CGFloat = Theme.gap
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
        if width < 780 { return 2 }
        if width < 1_170 { return 3 }
        if width < 1_570 { return 4 }
        return 5
    }

    private func columnWidth(in width: CGFloat, columns: Int) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func shortest(_ heights: [CGFloat]) -> Int {
        heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
    }
}

/// Shows 18 references at a time. Reaching the end reveals the next batch, then asks for another page.
struct LibraryGallery<MenuContent: View, Leading: View>: View {
    let items: [Reference]
    let more: Bool
    let loading: Bool
    /// True while any library request is in flight, including a background refresh.
    let busy: Bool
    let failed: Bool
    let viewport: CGRect
    let selecting: Bool
    let selectedIDs: Set<String>
    let resetID: String
    var scrollLive = LibraryScrollLive()
    var scrollTick = 0
    var onScrollPage: () -> Void = {}
    let open: (Reference) -> Void
    /// Nil where the gallery cannot select, such as search results.
    var toggle: ((Reference) -> Void)? = nil
    var brush: ((String, Bool) -> Void)? = nil
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent
    /// First tile of the masonry, such as the PRO tile on a free account.
    @ViewBuilder var leading: () -> Leading

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Session.self) private var session
    @State private var shown = GalleryPaging.batch
    @State private var gate = false
    /// Latest tail position. A class so scroll ticks do not invalidate the gallery.
    @State private var tail = GalleryTailPosition()
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var playingLoopIDs: Set<String> = []
    @State private var nearbyLoopIDs: Set<String> = []
    @State private var brushRemoves = false
    @State private var brushArmed = false
    @State private var brushPoint: CGPoint?

    private var visible: [Reference] { Array(items.prefix(shown)) }

    var body: some View {
        VStack(spacing: Theme.gap) {
            MasonryLayout(spacing: Theme.gap, forceColumns: typeSize.isAccessibilitySize ? 1 : nil) {
                leading()
                ForEach(visible) { reference in
                    LibraryCardCell(reference: reference, playsLoop: playingLoopIDs.contains(reference.id),
                                    selectable: toggle != nil,
                                    selecting: selecting, selected: selectedIDs.contains(reference.id),
                                    open: { open(reference) },
                                    toggleSelection: { toggle?(reference) }) {
                        menu(reference)
                    }
                    .id(reference.id)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background { loopProbe(reference) }
                    .background {
                        if selecting {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: GalleryCardFrames.self,
                                    value: [reference.id: proxy.frame(in: .named("galleryBrush"))]
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .scrollTargetLayout()
            if shown < items.count || more {
                GalleryPageTail { consider($0) }
                if loading {
                    ProgressView("Carregando mais referências…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("library.loadingMore")
                }
            }
        }
        .coordinateSpace(name: "galleryBrush")
        .onPreferenceChange(GalleryCardFrames.self) { frames in
            if frames != cardFrames { cardFrames = frames }
        }
        .onPreferenceChange(LoopWindowKey.self) { window in
            let playing = Set(visible.filter { window.playing.contains($0.id) }.prefix(InlineLoop.playerCap).map(\.id))
            if playing != playingLoopIDs { playingLoopIDs = playing }
            if window.nearby != nearbyLoopIDs {
                nearbyLoopIDs = window.nearby
                prefetchNearbyLoops(window.nearby)
            }
        }
        .modifier(SelectionBrush(enabled: selecting, gesture: brushGesture))
        .onChange(of: resetID) { _, _ in
            shown = GalleryPaging.batch
            gate = false
            scrollLive.armAgain()
        }
        #if os(macOS)
        .onChange(of: scrollTick, initial: true) { _, _ in reconsider() }
        .modifier(LegacyMacScrollProbe(live: scrollLive, onPage: onScrollPage))
        #endif
        .onChange(of: items.count) { old, new in
            // A page that arrives while the end gate is closed must still be shown.
            // `items` on a later retry is the array from before the append.
            let next = LibraryEndTrigger.nextShownCount(shown: shown, previousCount: old, newCount: new)
            if next != shown { shown = next }
            #if os(macOS)
            reconsider()
            #endif
        }
        .onChange(of: viewport) { _, _ in reconsider() }
        .onChange(of: busy) { _, busy in
            if !busy { reconsider() }
        }
        .onChange(of: more) { _, _ in reconsider() }
    }

    private var brushGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("galleryBrush"))
            .onChanged { value in
                #if os(iOS)
                guard selecting, brush != nil else { return }
                if !brushArmed {
                    brushArmed = true
                    brushRemoves = hit(value.startLocation).map { selectedIDs.contains($0) } ?? false
                    brushPoint = value.startLocation
                }
                paint(from: brushPoint ?? value.startLocation, to: value.location)
                brushPoint = value.location
                #endif
            }
            .onEnded { _ in
                brushArmed = false
                brushPoint = nil
            }
    }

    @ViewBuilder private func loopProbe(_ reference: Reference) -> some View {
        if reference.playsInlineLoop {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let near = viewport.isNull ? viewport : viewport.insetBy(dx: -80, dy: -InlineLoop.prefetchMargin)
                Color.clear.preference(
                    key: LoopWindowKey.self,
                    value: LoopWindow(
                        playing: viewport.intersects(frame) ? [reference.id] : [],
                        nearby: near.intersects(frame) ? [reference.id] : []
                    )
                )
            }
        }
    }

    private func prefetchNearbyLoops(_ ids: Set<String>) {
        guard let api = session.client(), let account = session.userID, !ids.isEmpty else { return }
        ImagePrefetch.warmMotion(visible.filter { ids.contains($0.id) }, client: api, account: account)
    }

    private func hit(_ point: CGPoint) -> String? {
        cardFrames.first { $0.value.contains(point) }?.key
    }

    private func paint(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let steps = max(1, Int(hypot(dx, dy) / 8))
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            guard let id = hit(CGPoint(x: start.x + dx * t, y: start.y + dy * t)) else { continue }
            brush?(id, !brushRemoves)
        }
    }

    private func consider(_ y: CGFloat) {
        tail.minY = y
        #if os(iOS)
        guard !gate else { return }
        guard LibraryEndTrigger.isNearEnd(tailMinY: y, viewport: viewport) else { return }
        reveal()
        #endif
    }

    /// `distance` is loaded content still below the visible bottom of the library scroll view.
    private func considerScrollDistance(_ distance: CGFloat, containerHeight: CGFloat) {
        guard !gate else { return }
        guard LibraryEndTrigger.shouldPage(distanceToEnd: distance, containerHeight: containerHeight) else { return }
        reveal()
    }

    private func reconsider() {
        #if os(macOS)
        considerScrollDistance(scrollLive.distance, containerHeight: scrollLive.containerHeight)
        #else
        consider(tail.minY)
        #endif
    }

    private func reveal() {
        guard !gate else { return }
        if shown < items.count {
            gate = true
            shown = min(items.count, shown + GalleryPaging.batch)
            disarm()
            return
        }
        guard !failed else { return }
        guard LibraryEndTrigger.shouldRequestNextPage(distanceToEnd: scrollLive.distance,
                                                       containerHeight: scrollLive.containerHeight,
                                                       hasCursor: more,
                                                       inFlight: loading) else { return }
        gate = true
        loadMore()
        disarm()
    }

    /// Lets layout publish a new tail position before another page can start.
    private func disarm() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            gate = false
            reconsider()
        }
    }
}

private enum GalleryPaging {
    static let batch = 18
}

/// Holds the page-tail offset without publishing a SwiftUI update on every scroll tick.
private final class GalleryTailPosition {
    var minY: CGFloat = .greatestFiniteMagnitude
}

/// Latest Mac scroll measurement. A class so offset ticks do not redraw the gallery.
@MainActor
final class LibraryScrollLive {
    var distance: CGFloat = .greatestFiniteMagnitude
    var containerHeight: CGFloat = 0
    private var signaled = false
    private var contentHeight: CGFloat = 0

    func apply(distance: CGFloat, containerHeight: CGFloat, contentHeight: CGFloat, onPage: () -> Void) {
        self.distance = distance
        self.containerHeight = containerHeight
        let page = LibraryEndTrigger.shouldPage(distanceToEnd: distance, containerHeight: containerHeight)
        let grew = contentHeight > self.contentHeight + 24
        self.contentHeight = contentHeight
        if page && (!signaled || grew) {
            signaled = true
            onPage()
        } else if !page {
            signaled = false
        }
    }

    func armAgain() {
        signaled = false
        contentHeight = 0
    }
}

/// macOS 15+ reads the scroll view's own geometry. Clip-view KVO does not fire while SwiftUI tracks.
private struct MacScrollGeometryPublisher: ViewModifier {
    var live: LibraryScrollLive
    var onPage: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.libraryScrollGeometry(live: live, onPage: onPage)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(macOS)
@available(macOS 15.0, *)
private struct LibraryScrollMeasurement: Equatable {
    var distance: CGFloat
    var containerHeight: CGFloat
    var contentHeight: CGFloat

    init(geometry geo: ScrollGeometry) {
        contentHeight = geo.contentSize.height
        containerHeight = geo.containerSize.height
        distance = LibraryEndTrigger.resolvedDistance(
            contentHeight: geo.contentSize.height,
            contentOffsetY: geo.contentOffset.y,
            containerHeight: geo.containerSize.height,
            visibleMaxY: geo.visibleRect.maxY,
            visibleHeight: geo.visibleRect.height)
    }
}

@available(macOS 15.0, *)
private extension View {
    func libraryScrollGeometry(live: LibraryScrollLive, onPage: @escaping () -> Void) -> some View {
        onScrollGeometryChange(for: LibraryScrollMeasurement.self) { geo in
            LibraryScrollMeasurement(geometry: geo)
        } action: { _, sample in
            live.apply(distance: sample.distance,
                       containerHeight: sample.containerHeight,
                       contentHeight: sample.contentHeight,
                       onPage: onPage)
        }
    }
}

/// macOS 14 has no scroll-geometry callback. The probe has to sit inside the scrolled content
/// and listen for clip-view bounds notifications — KVO on `bounds` never arrives during tracking.
private struct LegacyMacScrollProbe: ViewModifier {
    var live: LibraryScrollLive
    var onPage: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
        } else {
            content.background {
                LibraryScrollEndProbe { distance, container, contentHeight in
                    live.apply(distance: distance,
                               containerHeight: container,
                               contentHeight: contentHeight,
                               onPage: onPage)
                }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct LibraryScrollEndProbe: NSViewRepresentable {
    var onMeasure: (CGFloat, CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> LibraryScrollEndView {
        let view = LibraryScrollEndView()
        view.onMeasure = onMeasure
        return view
    }

    func updateNSView(_ view: LibraryScrollEndView, context: Context) {
        view.onMeasure = onMeasure
        view.attachIfNeeded()
    }
}

private final class LibraryScrollEndView: NSView {
    var onMeasure: ((CGFloat, CGFloat, CGFloat) -> Void)?
    private var attachedClip = false
    private var attachedDocument = false
    private var scheduled = false
    private var latest: (CGFloat, CGFloat, CGFloat) = (.greatestFiniteMagnitude, 0, 0)

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func layout() {
        super.layout()
        attachIfNeeded()
        note()
    }

    func attachIfNeeded() {
        guard let scroll = enclosingScrollView else { return }
        if !attachedClip {
            attachedClip = true
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
        if !attachedDocument, let document = scroll.documentView {
            attachedDocument = true
            document.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged),
                                                   name: NSView.frameDidChangeNotification, object: document)
        }
        note()
    }

    @objc private func scrollChanged(_ notification: Notification) {
        note()
    }

    private func note() {
        guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        let clip = scroll.contentView.bounds
        let visible = scroll.documentVisibleRect
        let contentHeight = max(document.frame.height, document.bounds.height)
        var offset = clip.origin.y
        if abs(offset) < 0.5, document.frame.origin.y < -1 {
            offset = -document.frame.origin.y
        }
        let visibleMaxY = document.isFlipped ? visible.maxY : (contentHeight - visible.minY)
        latest = (LibraryEndTrigger.resolvedDistance(contentHeight: contentHeight,
                                                     contentOffsetY: offset,
                                                     containerHeight: clip.height,
                                                     visibleMaxY: visibleMaxY,
                                                     visibleHeight: visible.height),
                  clip.height,
                  contentHeight)
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.onMeasure?(self.latest.0, self.latest.1, self.latest.2)
        }
    }
}
#endif

/// Installs the selection drag only while Selecionar is on. A drag left on the gallery
/// wins the pan and the library stops scrolling.
private struct SelectionBrush<G: Gesture>: ViewModifier {
    var enabled: Bool
    var gesture: G

    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content.simultaneousGesture(gesture)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Restores the top card per filter without writing the anchor through the observed
    /// store on every tick. That write was reapplying `scrollPosition` and cancelling the pan.
    func libraryScrollPosition() -> some View {
        modifier(LibraryScrollPosition())
    }
}

private struct LibraryScrollPosition: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @State private var id: String?
    @State private var filter = ""

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $id, anchor: .top)
            .onChange(of: store.filterKey, initial: true) { _, key in
                filter = key
                let saved = store.scrollAnchors[key]
                if id != saved { id = saved }
            }
            .onChange(of: id) { _, newID in
                guard filter == store.filterKey, let newID else { return }
                if store.scrollAnchors[filter] != newID {
                    store.scrollAnchors[filter] = newID
                }
            }
    }
}

/// iOS presents onboarding edge to edge. macOS has no full-screen cover, so it uses a sheet.
private struct OnboardingCover<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var cover: () -> Cover

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented, content: cover)
        #else
        content.sheet(isPresented: $isPresented, content: cover)
        #endif
    }
}

private struct LoopWindow: Equatable {
    var playing: Set<String> = []
    var nearby: Set<String> = []
}

private struct LoopWindowKey: PreferenceKey {
    static let defaultValue = LoopWindow()
    static func reduce(value: inout LoopWindow, nextValue: () -> LoopWindow) {
        let next = nextValue()
        value.playing.formUnion(next.playing)
        value.nearby.formUnion(next.nearby)
    }
}

private struct GalleryCardFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct GalleryTailKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct LibraryViewportKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension View {
    /// Publishes the scroll view's visible frame so paging uses the window, not the whole screen.
    func libraryViewport() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: LibraryViewportKey.self, value: geo.frame(in: .global))
            }
        }
    }
}

/// Reports its position in screen space. The gallery compares that with the scroll view's frame.
private struct GalleryPageTail: View {
    let onMove: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: GalleryTailKey.self, value: geo.frame(in: .global).minY)
                }
            }
            .onPreferenceChange(GalleryTailKey.self, perform: onMove)
            .accessibilityHidden(true)
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
