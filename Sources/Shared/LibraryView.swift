import SwiftUI
import QueepCore
#if os(macOS)
import AppKit
#else
import PhotosUI
import UIKit
#endif

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var logoutError: String?
    @State private var actionError: String?
    @State private var pendingDelete: Reference?
    @State private var pendingSelectionDelete: [Reference] = []
    @State private var macHeaderHeight: CGFloat = 140
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var spaceSelection: [Reference] = []
    @State private var pickingSpaces = false
    @AppStorage("queep.firstSearchHint.dismissed") private var searchHintDismissed = false
    @State private var onboardingPresented = false
    @State private var onboardingDismissed = false
    @State private var sawEmptyLibrary = false
    @State private var conversionOffer: ConversionFocus?
    @State private var consideringFirstPaywall = false
    #if os(iOS)
    @State private var galleryPhoto: PhotosPickerItem?
    @State private var sendingPhoto = false
    #endif

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
            .subscriptionGate(enabled: store.presentation == nil)
            .sheet(item: sheetPresentation) { presentation in
                switch presentation {
                case .account: AccountView()
                case .usage: UsagePrivacyView()
                case .help: HelpView()
                case .deleteAccount: DeleteAccountView()
                case .subscription: SubscriptionView()
                case .newSpace: SpaceNameSheet()
                case .capture:
                    if store.captureKind == "link" && (store.captureIntent == "post" || store.captureIntent == "site") {
                        LinkCaptureView()
                    } else {
                        CaptureView(reference: nil, initialKind: store.captureKind)
                    }
                case .reference(let reference):
                    if GalleryDetailView.supports(reference) {
                        GalleryDetailView(reference: reference, items: galleryItems) { store.presentation = nil }
                            #if os(iOS)
                            .presentationDragIndicator(.hidden)
                            #endif
                    } else {
                        LiveReferenceView(reference: reference) { live in
                            ReferenceDetail(reference: live)
                        }
                    }
                }
            }
            .alert("Não foi possível sair", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK") { logoutError = nil }
            } message: { Text(logoutError ?? "") }
            .alert("Não foi possível concluir", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: { Text(actionError ?? "") }
            #if os(iOS)
            .photosPicker(isPresented: $store.openPhotoLibrary, selection: $galleryPhoto,
                          matching: .images, preferredItemEncoding: .current)
            .onChange(of: galleryPhoto) { _, item in
                guard let item else { return }
                galleryPhoto = nil
                Task { await sendGalleryPhoto(item) }
            }
            #endif
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
                    selecting = false
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
            selecting = false
            selectedIDs = []
            Task {
                await refresh()
                if !store.searchChips.isEmpty { await search() }
            }
        }
        .onChange(of: store.surface) { _, _ in
            selecting = false
            selectedIDs = []
            Task { await refresh() }
        }
        .onAppear {
            noteEmptyLibrary()
            presentOnboardingIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-paywall") {
                conversionOffer = .pro
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
        }
        .onChange(of: onboardingPresented) { _, _ in considerFirstPaywall() }
        .onboardingCover(isPresented: $onboardingPresented) {
            OnboardingFlow {
                onboardingDismissed = true
                onboardingPresented = false
            }
        }
        .sheet(item: $conversionOffer) { focus in
            ConversionPaywall(focus: focus)
        }
        .task(id: session.userID) { await restoreOnboarding() }
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
            if decision == .show { conversionOffer = .pro }
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
        @Bindable var store = store
        #if os(macOS)
        ZStack(alignment: .top) {
            ScrollView {
                libraryContents
                    .padding(.horizontal, 16).padding(.bottom, 36)
                    .padding(.top, max(8, macHeaderHeight))
                    .frame(maxWidth: .infinity)
            }
            .libraryScrollPosition()
            MacLibraryHeader(search: { Task { await search() } }, refresh: { Task { await refresh() } })
                .homeTopBar()
                .onPreferenceChange(HomeTopBarHeightKey.self) { macHeaderHeight = $0 }
        }
        .overlay { macGallery }
        .animation(.easeOut(duration: 0.15), value: macGalleryID)
        .background(Color.white)
        .preferredColorScheme(.light)
        .hideMacWindowTitle()
        #else
        iPhoneLibrary(
            search: { Task { await search() } },
            refresh: { await refresh() },
            selecting: selecting,
            canSelect: !store.items.isEmpty && !searching && !(store.surface == .spaces && store.selectedSpaceID == nil),
            toggleSelect: {
                selecting.toggle()
                if !selecting { selectedIDs = [] }
            },
            content: { libraryContents },
            dock: { if selecting { selectionDock } }
        )
        .background(Color.white)
        .preferredColorScheme(.light)
        #endif
    }

    private var libraryContents: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            if session.isLocal {
                Label("Versão de desenvolvimento local", systemImage: "hammer")
                    .font(.caption).foregroundStyle(Color.muted).padding(.horizontal, 4)
            }
            #endif
            if store.surface == .spaces, store.selectedSpaceID == nil {
                SpacesOverview()
            } else {
            #if os(macOS)
            if store.surface == .spaces, store.selectedSpaceID != nil {
                Button { store.selectSpace(nil) } label: {
                    Label("Spaces", systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.homeInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spaces")
                .accessibilityIdentifier("spaces.back")
            }
            #endif
            if store.surface == .spaces, let space = store.selectedSpace {
                Text(space.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.homeInk)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            if store.surface == .archived {
                Text("Arquivados")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.homeInk)
                    .accessibilityAddTraits(.isHeader)
            }
            if !store.items.isEmpty && !searching && !(store.surface == .spaces && store.selectedSpaceID == nil) {
                #if os(macOS)
                HStack(spacing: 8) {
                    if selecting { selectionActions }
                    Button {
                        selecting.toggle()
                        if !selecting { selectedIDs = [] }
                    } label: { GalleryChip(title: selecting ? "Cancelar" : "Selecionar") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.select")
                }
                #endif
            }
            #if os(iOS)
            if sendingPhoto {
                Label("Enviando imagem…", systemImage: "arrow.up.circle")
                    .font(.callout)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14, elevated: false)
                    .accessibilityIdentifier("library.sendingPhoto")
            }
            #endif
            if let error = store.error {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Tentar novamente") { Task { await refresh() } }
                }.card(padding: 14, elevated: false)
            }
            if store.surface == .home && store.items.count == 1 && !searching && !searchHintDismissed && conversionOffer == nil {
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
                if store.surface == .archived {
                    ContentUnavailableView("Nenhum item arquivado", systemImage: "archivebox",
                        description: Text("Itens arquivados saem da biblioteca ativa e continuam guardados aqui."))
                } else if store.surface == .spaces && store.selectedSpaceID != nil {
                    EmptySpaceView()
                } else if store.surface == .home && store.hasArchivedItems {
                    ContentUnavailableView("Tudo arquivado", systemImage: "archivebox.fill",
                        description: Text("Sua biblioteca ativa está vazia. Em Ajustes, abra Arquivados para restaurar itens."))
                } else {
                    FirstUseView(scrolls: false)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label(searching ? "Nada parecido por aqui" : store.kindFilter == nil ? "Seu espaço para lembrar" : "Nada neste filtro",
                          systemImage: searching ? "sparkle.magnifyingglass" : "bookmark")
                } description: {
                    Text(searching ? (store.surface == .archived
                         ? "Nenhum arquivado tem esse título ou endereço."
                         : "Nenhuma correspondência entre os candidatos analisados. Tente descrever de outro jeito.")
                         : store.kindFilter == nil
                         ? "Guarde uma imagem, um link ou uma nota. Eles aparecem nos seus dispositivos."
                         : "Esse tipo ainda não está na biblioteca. Queep things guarda o próximo.")
                } actions: {
                    if !searching { Button("Adicionar referência") { store.startCapture() }.buttonStyle(.borderedProminent) }
                }
            } else {
                LibraryGallery(items: filtered, more: !searching && store.nextCursor != nil,
                               loading: store.loading, failed: store.error != nil,
                               selecting: selecting, selectedIDs: selectedIDs,
                               resetID: "\(store.filterKey)|\(store.kindFilter ?? "")|\(searching)",
                               open: { open($0) },
                               brush: { id, include in
                                   if include {
                                       if selectedIDs.count < 50 { selectedIDs.insert(id) }
                                   } else {
                                       selectedIDs.remove(id)
                                   }
                               },
                               loadMore: {
                    Task {
                        guard let api = session.client(), let uid = session.userID else { return }
                        await store.refresh(api, account: uid, more: true)
                    }
                }, menu: { cardMenu($0) })
            }
            }
        }
    }

    /// Right-click on the Mac, long-press on iPhone: the basics without opening the item.
    @ViewBuilder private func cardMenu(_ reference: Reference) -> some View {
        Button("Abrir", systemImage: "arrow.up.right.square") { store.presentation = .reference(reference) }
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

    /// iPhone floating bar. Spaces is the wide primary action; archive and delete stay compact.
    private var selectionDock: some View {
        HStack(spacing: 6) {
            Text(selectionCountLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 96, alignment: .leading)
            Button(action: assignSelectionToSpaces) {
                Text("Spaces")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            .accessibilityIdentifier("library.spaceSelection")
            HStack(spacing: 0) {
                Button(action: archiveSelection) {
                    Text(store.surface == .archived ? "Desarquivar" : "Arquivar")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .accessibilityIdentifier("library.archiveSelection")
                Button(action: deleteSelection) {
                    Text("Excluir")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .accessibilityIdentifier("library.deleteSelection")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private var selectionActions: some View {
        HStack(spacing: 8) {
            Text(selectionCountLabel)
                .font(.system(size: 13, weight: .medium)).tracking(-0.2)
                .foregroundStyle(GalleryStyle.secondary)
                .padding(.trailing, 4)
            Button(action: assignSelectionToSpaces) {
                GalleryChip(title: "Spaces", symbol: "square.stack.3d.up", selected: true)
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty).opacity(selectedIDs.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("library.spaceSelection")
            Button(action: archiveSelection) {
                GalleryChip(title: store.surface == .archived ? "Desarquivar" : "Arquivar")
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty).opacity(selectedIDs.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("library.archiveSelection")
            Button(action: deleteSelection) {
                GalleryChip(title: "Excluir")
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty).opacity(selectedIDs.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("library.deleteSelection")
        }
    }

    private func assignSelectionToSpaces() {
        spaceSelection = filtered.filter { selectedIDs.contains($0.id) }
        pickingSpaces = !spaceSelection.isEmpty
    }

    private func archiveSelection() {
        let chosen = filtered.filter { selectedIDs.contains($0.id) }
        archive(chosen, archived: store.surface != .archived)
        selecting = false
        selectedIDs = []
    }

    private func deleteSelection() {
        pendingSelectionDelete = filtered.filter { selectedIDs.contains($0.id) }
    }

    private var galleryItems: [Reference] { filtered.filter(GalleryDetailView.supports) }

    /// On the Mac the opened picture covers the library like saved.design; everything else is a sheet.
    private var sheetPresentation: Binding<LibraryPresentation?> {
        Binding(get: {
            #if os(macOS)
            if case .reference(let reference) = store.presentation, GalleryDetailView.supports(reference) { return nil }
            #endif
            return store.presentation
        }, set: { store.presentation = $0 })
    }

    #if os(macOS)
    private var macGalleryID: String? {
        if case .reference(let reference) = store.presentation, GalleryDetailView.supports(reference) { return reference.id }
        return nil
    }

    @ViewBuilder private var macGallery: some View {
        if case .reference(let reference) = store.presentation, GalleryDetailView.supports(reference) {
            GalleryDetailView(reference: reference, items: galleryItems) { store.presentation = nil }
                .transition(.opacity)
        }
    }
    #endif

    @ViewBuilder private var archiveToast: some View {
        if let undo = store.archiveUndo {
            HStack(spacing: 16) {
                Label(undo.references.count == 1 ? "Arquivado" : "\(undo.references.count) arquivados",
                      systemImage: "archivebox")
                Button("Desfazer") {
                    guard let api = session.client(), let uid = session.userID else { return }
                    store.undoArchive(undo, client: api, account: uid)
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 12, y: 4)
            .padding(.bottom, 24)
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
            if selectedIDs.contains(reference.id) { selectedIDs.remove(reference.id) }
            else if selectedIDs.count < 50 { selectedIDs.insert(reference.id) }
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
        await store.refresh(api, account: uid)
        if let failure { actionError = failure }
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

    #if os(iOS)
    private func sendGalleryPhoto(_ selection: PhotosPickerItem) async {
        guard !sendingPhoto else { return }
        sendingPhoto = true
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
            await store.refresh(api, account: uid)
        } catch is CancellationError {
        } catch let failure as QueepError {
            if case .planRequired = failure { return }
            actionError = failure.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }
    #endif
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

/// Masonry with saved.design's breakpoints: two columns on the phone, up to five on a wide window.
struct MasonryLayout: Layout {
    var spacing: CGFloat = GalleryStyle.gap
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
struct LibraryGallery<MenuContent: View>: View {
    let items: [Reference]
    let more: Bool
    let loading: Bool
    let failed: Bool
    let selecting: Bool
    let selectedIDs: Set<String>
    let resetID: String
    let open: (Reference) -> Void
    var brush: ((String, Bool) -> Void)? = nil
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shown = GalleryPaging.batch
    @State private var gate = false
    /// Scroll position of the page tail. A class so each pan tick does not invalidate the gallery.
    @State private var tail = GalleryTailPosition()
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var brushRemoves = false
    @State private var brushArmed = false
    @State private var brushPoint: CGPoint?

    private var visible: [Reference] { Array(items.prefix(shown)) }

    var body: some View {
        VStack(spacing: GalleryStyle.gap) {
            MasonryLayout(spacing: GalleryStyle.gap, forceColumns: typeSize.isAccessibilitySize ? 1 : nil) {
                ForEach(visible) { reference in
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
        .modifier(SelectionBrush(enabled: selecting, gesture: brushGesture))
        .onChange(of: resetID) { _, _ in
            shown = GalleryPaging.batch
            gate = false
        }
        .onChange(of: items.count) { old, new in
            if new < old { shown = min(GalleryPaging.batch, new) }
            if !gate { consider(tail.y) }
        }
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
        tail.y = y
        guard y < viewportHeight + 320 else { return }
        reveal()
    }

    private func reveal() {
        guard !gate else { return }
        if shown < items.count {
            gate = true
            shown = min(items.count, shown + GalleryPaging.batch)
            release()
            return
        }
        guard more, !loading, !failed else { return }
        gate = true
        loadMore()
        release()
    }

    private func release() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            gate = false
            consider(tail.y)
        }
    }

    private var viewportHeight: CGFloat {
        #if os(macOS)
        NSScreen.main?.visibleFrame.height ?? 900
        #else
        UIScreen.main.bounds.height
        #endif
    }
}

private enum GalleryPaging {
    static let batch = 18
}

/// Holds the page-tail offset without publishing a SwiftUI update on every scroll tick.
private final class GalleryTailPosition {
    var y: CGFloat = .greatestFiniteMagnitude
}

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

/// Reports its distance from the top of the screen so the gallery can reveal the next batch.
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

/// Keeps detail sheets on the freshest library copy while polling updates the store.
private struct LiveReferenceView<Content: View>: View {
    @Environment(LibraryStore.self) private var store
    let reference: Reference
    @ViewBuilder var content: (Reference) -> Content

    var body: some View {
        content(store.items.first(where: { $0.id == reference.id }) ?? reference)
    }
}


private extension View {
    @ViewBuilder
    func onboardingCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
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
