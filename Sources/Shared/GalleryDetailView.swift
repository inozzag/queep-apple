import AVKit
import SwiftUI
import QueepCore

/// Chip from saved.design's filter row: black when selected, light gray otherwise.
struct GalleryChip: View {
    let title: String
    var symbol: String?
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 13, weight: .medium)).tracking(-0.2).lineLimit(1)
        }
        .foregroundStyle(selected ? GalleryStyle.onInk : GalleryStyle.secondary)
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(selected ? GalleryStyle.ink : GalleryStyle.fill, in: Capsule())
        #if os(iOS)
        .padding(.vertical, 4)
        #endif
        .contentShape(Rectangle())
        .fixedSize()
    }
}

/// Rounded action from saved.design's opened item: gray, or black for the main action.
struct GalleryPill: View {
    var title: String?
    var leading: String?
    var trailing: String?
    var dark = false
    var height: CGFloat = 36
    var stretches = false

    var body: some View {
        HStack(spacing: 6) {
            if let leading { Image(systemName: leading).font(.system(size: 11, weight: .semibold)) }
            if let title { Text(title).font(.system(size: 13, weight: .medium)).tracking(-0.2).lineLimit(1) }
            if let trailing { Image(systemName: trailing).font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(dark ? Color.white : GalleryStyle.secondary)
        .padding(.horizontal, title == nil ? 0 : 16)
        .frame(width: title == nil ? height : nil, height: height)
        .frame(maxWidth: stretches ? .infinity : nil)
        .background(dark ? GalleryStyle.ink : GalleryStyle.fill, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Full detail with editing, notes and the AI reading.
struct ReferenceDetail: View {
    let reference: Reference

    var body: some View {
        if reference.isSocialProfile { ProfileDetailView(reference: reference) }
        else if reference.isSocialPost { PostDetailView(reference: reference) }
        else if reference.isWebsite { SiteDetailView(reference: reference) }
        else if reference.kind == "image" { ImageDetailView(reference: reference) }
        else if reference.media != nil { MediaDetailView(reference: reference) }
        else { CaptureView(reference: reference) }
    }
}

/// Opened picture in saved.design's layout: title, source and actions above a centered carousel,
/// with previous and next moving through the gallery. Editing stays in the full detail.
struct GalleryDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    private let initial: Reference
    private let items: [Reference]
    private let close: () -> Void
    @State private var currentID: String
    @State private var page: Int? = 0
    @State private var editing: Reference?
    @State private var pickingSpace = false
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var error: String?
    @State private var pollEpoch = 0
    @State private var player: AVPlayer?
    @State private var file: TemporaryMediaFile?

    init(reference: Reference, items: [Reference], close: @escaping () -> Void) {
        initial = reference
        self.items = items.contains { $0.id == reference.id } ? items : [reference]
        self.close = close
        _currentID = State(initialValue: reference.id)
    }

    private var current: Reference {
        store.reference(currentID) ?? items.first { $0.id == currentID } ?? initial
    }
    private var position: Int? { items.firstIndex { $0.id == currentID } }
    private var previous: Reference? { position.flatMap { $0 > 0 ? items[$0 - 1] : nil } }
    private var next: Reference? { position.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil } }
    private var identity: PostIdentity { PostIdentity(current) }
    private var host: String? { current.url.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") } }
    private var originalURL: URL? { current.url.flatMap(URL.init(string:)) }
    private var slideCount: Int {
        if current.kind == "video", current.media != nil { return 1 }
        return current.gallery.count
    }
    private var hasSlides: Bool { slideCount > 0 }
    private var slide: Int { min(max(page ?? 0, 0), max(slideCount - 1, 0)) }

    private var canEdit: Bool {
        !current.isArchived && !current.isSocialProfile
            && ["note", "link", "image", "audio", "video"].contains(current.kind)
    }

    private var title: String {
        if current.isSocialPost || current.isSocialProfile {
            return [identity.title, identity.author, current.linkSurface?.brandName ?? ""]
                .first { !$0.isEmpty } ?? current.displayTitle
        }
        if current.kind == "link" {
            let own = current.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !own.isEmpty { return own }
            if let name = current.source?.title, !name.isEmpty { return name }
            return host ?? current.displayTitle
        }
        return current.displayTitle
    }

    private var summary: String {
        if (current.isSocialPost || current.isSocialProfile), !identity.body.isEmpty { return identity.body }
        if let text = current.analysis?.summary, !text.isEmpty { return text }
        return Markdown.plainText(current.text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authorName: String? {
        if current.isSocialPost || current.isSocialProfile {
            let name = identity.author.isEmpty ? identity.handle : identity.author
            if name.isEmpty { return nil }
            if name == title { return identity.handle.isEmpty || identity.handle == name ? nil : identity.handle }
            return name
        }
        if current.kind == "link" {
            if let name = current.source?.title, !name.isEmpty, name != title { return name }
            return host
        }
        return nil
    }

    private var tag: String {
        if let surface = current.linkSurface, surface != .website { return surface.brandName }
        return current.kindLabel
    }

    var body: some View {
        GeometryReader { geo in
            #if os(macOS)
            desktop(geo.size)
            #else
            phone(geo.size)
            #endif
        }
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .sheet(item: $editing, onDismiss: reconcile) { item in
            GalleryEditSheet(reference: store.reference(item.id) ?? item)
        }
        .sheet(isPresented: $pickingSpace) { SpacePicker(references: [current]) }
        .confirmationDialog("Excluir permanentemente esta referência?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Excluir", role: .destructive) { Task { await remove() } }
        } message: { Text("Arquivar esconde. Excluir apaga da sua conta.") }
        .task(id: "\(session.userID ?? "")/\(currentID)") { await loadVideo() }
        .task(id: "poll/\(session.userID ?? "")/\(currentID)/\(pollEpoch)") { await pollAnalysis() }
        .onDisappear { clearPlayer() }
        .accessibilityIdentifier("gallery.detail")
    }

    #if os(macOS)
    private func desktop(_ size: CGSize) -> some View {
        let column = min(600, max(360, size.width - 416))
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header.frame(width: column).padding(.top, 32)
                GeometryReader { box in
                    VStack(spacing: 20) {
                        slides(height: max(220, box.size.height - 96), spacing: 64, chevronInset: 96,
                               chevronFill: GalleryStyle.fill)
                        dots
                    }
                    .padding(.top, 32)
                }
            }
            HStack(alignment: .top) {
                Button(action: close) { GalleryPill(title: "Esc", leading: "xmark") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("gallery.close")
                Spacer()
                HStack(spacing: 8) {
                    navButton(previous: true)
                    navButton(previous: false)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    titleText
                if !summary.isEmpty {
                    summaryText.lineLimit(3).frame(maxWidth: 440, alignment: .leading)
                }
                analysisExtras
                analysisStatus
                }
                Spacer(minLength: 16)
                author.frame(maxWidth: 220, alignment: .trailing)
            }
            Rectangle().fill(GalleryStyle.ring).frame(height: 1).padding(.top, 14)
            HStack(spacing: 6) {
                tagPill
                Spacer(minLength: 12)
                moreMenu(height: 36)
                shareButton(stretches: false)
                originalButton(stretches: false)
            }
            .padding(.top, 16)
            if error != nil { errorText.padding(.top, 10) }
        }
    }
    #else
    private func phone(_ size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                slides(height: min(480, max(260, size.height * 0.42)), spacing: 12, chevronInset: 28,
                       chevronFill: .white.opacity(0.85))
                    .padding(.top, 24)
                dots.frame(maxWidth: .infinity).padding(.top, 16)
                HStack(spacing: 8) {
                    Button(action: close) { GalleryPill(leading: "xmark", height: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fechar")
                        .accessibilityIdentifier("gallery.close")
                    Spacer()
                    moreMenu(height: 44)
                    navButton(previous: true)
                    navButton(previous: false)
                }
                .padding(.horizontal, GalleryStyle.inset)
                .padding(.top, 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GalleryStyle.tertiary)
                    titleText
                    author
                    if !summary.isEmpty { summaryText }
                    analysisExtras
                    analysisStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GalleryStyle.inset)
                .padding(.top, 24)
                VStack(spacing: 8) {
                    shareButton(stretches: true)
                    originalButton(stretches: true)
                }
                .padding(.horizontal, GalleryStyle.inset)
                .padding(.top, 24)
                if error != nil { errorText.padding(.horizontal, GalleryStyle.inset).padding(.top, 12) }
            }
            .padding(.bottom, 32)
        }
    }
    #endif

    private var titleText: some View {
        Text(title)
            .font(.system(size: 17, weight: .medium))
            .tracking(-0.4)
            .foregroundStyle(GalleryStyle.ink)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("gallery.title")
    }

    @ViewBuilder private var analysisStatus: some View {
        if current.galleryStatusLine != nil || (current.showsAnalysisRetry && !busy) {
            VStack(alignment: .leading, spacing: 8) {
                if let line = current.galleryStatusLine {
                    Text(line)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(current.status == "queued" || current.status == "processing"
                                         ? GalleryStyle.secondary : GalleryStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gallery.status")
                }
                if current.showsAnalysisRetry && !busy {
                    Button {
                        Task { await retryAnalysis() }
                    } label: {
                        GalleryPill(title: "Analisar de novo", leading: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        }
    }

    private var summaryText: some View {
        Text(summary)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(GalleryStyle.secondary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var author: some View {
        HStack(spacing: 8) {
            SourceBadge(reference: current, size: 28)
            if let authorName {
                Text(authorName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GalleryStyle.ink)
                    .lineLimit(1)
            }
        }
    }

    private var tagPill: some View {
        Text(tag)
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.2)
            .foregroundStyle(GalleryStyle.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .overlay { Capsule().strokeBorder(GalleryStyle.ring) }
    }

    private var errorText: some View {
        Label(error ?? "", systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.red)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(slideCount, 1), id: \.self) { index in
                Circle()
                    .fill(index == slide ? GalleryStyle.ink : GalleryStyle.dot)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
        .opacity(slideCount > 1 ? 1 : 0)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func slides(height: CGFloat, spacing: CGFloat, chevronInset: CGFloat, chevronFill: Color) -> some View {
        if current.kind == "audio" {
            VStack(spacing: 16) {
                HomeReferenceCard(reference: current)
                    .frame(maxWidth: 480)
                if let player {
                    MediaPlaybackView(player: player, video: false, duration: current.media?.durationSeconds ?? 0)
                        .padding(16)
                        .frame(maxWidth: 480)
                        .background(GalleryStyle.fill, in: RoundedRectangle(cornerRadius: GalleryStyle.radius, style: .continuous))
                } else if current.media != nil {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .id(currentID)
        } else if hasSlides {
            GallerySlides(reference: current, height: height, spacing: spacing, player: player,
                          chevronInset: chevronInset, chevronFill: chevronFill, page: $page)
                .id(currentID)
        } else {
            HomeReferenceCard(reference: current)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .id(currentID)
        }
    }

    @ViewBuilder private var analysisExtras: some View {
        if current.status == "ready", let topics = current.analysis?.topics.filter({ !$0.isEmpty }), !topics.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(topics.prefix(8).enumerated()), id: \.offset) { _, topic in
                        GalleryChip(title: topic)
                    }
                }
            }
            .accessibilityIdentifier("gallery.topics")
        }
        if let transcript = current.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
            Text("Transcrição")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GalleryStyle.tertiary)
            Text(transcript)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GalleryStyle.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("media.transcript")
        }
    }

    private func navButton(previous isPrevious: Bool) -> some View {
        let target = isPrevious ? previous : next
        return Button { show(target) } label: {
            #if os(macOS)
            GalleryPill(title: isPrevious ? "Anterior" : "Próximo",
                        leading: isPrevious ? "chevron.left" : nil,
                        trailing: isPrevious ? nil : "chevron.right")
            #else
            GalleryPill(leading: isPrevious ? "chevron.left" : "chevron.right", height: 44)
            #endif
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
        .keyboardShortcut(isPrevious ? .leftArrow : .rightArrow, modifiers: [])
        .accessibilityLabel(isPrevious ? "Referência anterior" : "Próxima referência")
        .accessibilityIdentifier(isPrevious ? "gallery.previous" : "gallery.next")
    }

    private func moreMenu(height: CGFloat) -> some View {
        Menu {
            if canEdit {
                Button("Editar", systemImage: "square.and.pencil") { editing = current }
                    .accessibilityIdentifier("reference.edit")
            }
            if !current.isArchived {
                Button("Space", systemImage: "square.stack.3d.up") { pickingSpace = true }
                    .accessibilityIdentifier("reference.space")
            }
            if let url = current.url {
                Button("Copiar link", systemImage: "link") { Clipboard.copy(url) }
            }
            Divider()
            Button(current.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: current.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("reference.archive")
            Button("Excluir…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .disabled(busy)
                .accessibilityIdentifier("reference.delete")
        } label: {
            GalleryPill(leading: "ellipsis", height: height)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .accessibilityLabel("Mais")
        .accessibilityIdentifier("reference.more")
    }

    @ViewBuilder private func shareButton(stretches: Bool) -> some View {
        if let originalURL {
            ShareLink(item: originalURL) {
                GalleryPill(title: "Compartilhar", trailing: "square.and.arrow.up",
                            height: stretches ? 44 : 36, stretches: stretches)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.share")
        }
    }

    @ViewBuilder private func originalButton(stretches: Bool) -> some View {
        if let originalURL {
            Button { openURL(originalURL) } label: {
                GalleryPill(title: "Ver original", trailing: "arrow.up.right.square",
                            dark: true, height: stretches ? 44 : 36, stretches: stretches)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("post.openOriginal")
        } else if canEdit {
            Button { editing = current } label: {
                GalleryPill(title: "Editar", trailing: "square.and.pencil",
                            dark: true, height: stretches ? 44 : 36, stretches: stretches)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.edit.open")
        }
    }

    private func retryAnalysis() async {
        guard let api = session.client(), let uid = session.userID else { return }
        let target = current
        busy = true
        error = nil
        defer { busy = false }
        do {
            let value = try await api.retryAnalysis(target)
            guard session.userID == uid else { return }
            store.adopt(value)
            if AnalysisPoll.resumes(afterRetry: value.status) {
                pollEpoch += 1
            }
        } catch {
            self.error = AnalysisRetry.failureCopy(error)
        }
    }

    /// Follow a queued or processing item until it is ready, fails, or the picture arrives.
    private func pollAnalysis() async {
        guard let uid = session.userID else { return }
        let id = currentID
        let starting = store.reference(id) ?? items.first { $0.id == id } ?? initial
        guard !starting.isArchived else { return }
        guard starting.status == "queued" || starting.status == "processing" else { return }
        await AnalysisPolling.run(
            policy: starting.expectsPicture ? .post : .detail,
            interval: .seconds(5),
            fetch: {
                guard let api = session.client(), session.userID == uid else { throw CancellationError() }
                return try await api.get(id: id)
            },
            apply: { value in
                store.adopt(value)
                error = nil
            },
            onFailure: { error = $0 }
        )
    }

    private func show(_ target: Reference?) {
        guard let target else { return }
        clearPlayer()
        error = nil
        page = 0
        currentID = target.id
        ProductAnalytics.referenceOpened(kind: target.kind, url: target.url)
    }

    private func archive() {
        guard let api = session.client(), let uid = session.userID else { return }
        let target = current
        clearPlayer()
        store.setArchived([target], archived: !target.isArchived, client: api, account: uid)
        close()
    }

    private func remove() async {
        guard let api = session.client(), let uid = session.userID else { return }
        let target = current
        busy = true
        defer { busy = false }
        do {
            try await api.delete(target)
            guard session.userID == uid else { return }
            clearPlayer()
            store.discardSearchReference(target.id)
            await store.refresh(api, account: uid, force: true)
            close()
        } catch { self.error = error.localizedDescription }
    }

    /// The full detail can archive or delete; leave when the item is no longer in the library.
    private func reconcile() {
        let id = currentID
        let listed = store.items.contains { $0.id == id } || store.searchItems?.contains { $0.id == id } == true
        if !listed { close() }
    }

    private func loadVideo() async {
        clearPlayer()
        let target = current
        let audio = target.kind == "audio" && target.media != nil
        let video = target.kind == "video" && target.media != nil && target.media?.loop != true
        guard audio || video, let api = session.client(), let owner = session.userID else { return }
        do {
            let data = try await api.mediaData(target)
            guard !Task.isCancelled, owner == session.userID, target.id == currentID else { return }
            let temporary = TemporaryMediaFile(extension: audio ? "m4a" : "mp4")
            try data.write(to: temporary.url, options: .atomic)
            file = temporary
            player = AVPlayer(url: temporary.url)
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func clearPlayer() {
        player?.pause()
        player = nil
        file = nil
    }
}

/// Title and notes on the gallery surface. Analysis stays on the opened item.
private struct GalleryEditSheet: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reference: Reference
    @State private var title: String
    @State private var text: String
    @State private var busy = false
    @State private var error: String?

    init(reference: Reference) {
        self.reference = reference
        _title = State(initialValue: reference.title)
        _text = State(initialValue: reference.text)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { trimmedTitle != reference.title || text != reference.text }
    private var canSave: Bool {
        guard !busy, !reference.isArchived, changed, trimmedTitle.count <= 200, text.count <= 30_000 else { return false }
        if reference.kind == "note" { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { dismiss() } label: { GalleryPill(title: "Fechar", leading: "xmark") }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityIdentifier("gallery.edit.close")
                Spacer()
                Text("Editar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GalleryStyle.ink)
            }
            TextField("Título", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(GalleryStyle.ink)
                .lineLimit(1...3)
                .accessibilityLabel("Título")
                .accessibilityIdentifier("gallery.edit.title")
            Text("Notas")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GalleryStyle.tertiary)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(GalleryStyle.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(12)
                .background(GalleryStyle.fill, in: RoundedRectangle(cornerRadius: GalleryStyle.radius, style: .continuous))
                .accessibilityLabel("Notas")
                .accessibilityIdentifier("gallery.edit.text")
            if trimmedTitle.count > 200 {
                Text("O título tem no máximo 200 caracteres.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GalleryStyle.secondary)
            }
            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await save() } } label: {
                Text(busy ? "Salvando…" : "Salvar")
            }
            .buttonStyle(MasterButtonStyle())
            .disabled(!canSave)
            .accessibilityIdentifier("gallery.edit.save")
        }
        .padding(24)
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("gallery.edit")
    }

    private func save() async {
        guard let api = session.client(), let uid = session.userID, canSave else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let value: Reference
            if reference.kind == "note" {
                value = try await api.edit(reference, capture: Capture(kind: "note", title: trimmedTitle, text: text),
                                            mutationID: UUID())
            } else {
                value = try await api.editMetadata(reference, title: trimmedTitle, text: text, mutationID: UUID())
            }
            guard session.userID == uid else { return }
            store.adopt(value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Poster first, then the stored mp4 when the save actually has one.
private struct PreviewClip: View {
    @Environment(Session.self) private var session
    let reference: Reference
    let index: Int
    @State private var player: AVPlayer?
    @State private var file: TemporaryMediaFile?

    var body: some View {
        ZStack {
            RemoteImage(reference: reference, thumbnail: true, fill: true, index: index)
            if let player {
                VideoPlayer(player: player)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background { Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark) }
                    .clipShape(Circle())
                    .allowsHitTesting(false)
            }
        }
        .task(id: "\(reference.id)/\(index)") { await load() }
        .onDisappear { clear() }
    }

    private func load() async {
        guard let api = session.client(), let owner = session.userID else { return }
        do {
            let data = try await api.imageData(reference, index: index, role: "clip")
            guard !Task.isCancelled, owner == session.userID, !data.isEmpty else { return }
            let temporary = TemporaryMediaFile(extension: "mp4")
            try data.write(to: temporary.url, options: .atomic)
            file = temporary
            let clip = AVPlayer(url: temporary.url)
            clip.isMuted = true
            clip.volume = 0
            player = clip
        } catch is CancellationError {
        } catch {
            clear()
        }
    }

    private func clear() {
        player?.pause()
        player = nil
        file = nil
    }
}

/// Media at a fixed height, keeping each picture's proportions; the current one sits centered.
private struct GallerySlides: View {
    let reference: Reference
    let height: CGFloat
    let spacing: CGFloat
    let player: AVPlayer?
    let chevronInset: CGFloat
    let chevronFill: Color
    @Binding var page: Int?

    private var isVideo: Bool { reference.kind == "video" && reference.media != nil }
    private var count: Int { isVideo ? 1 : reference.gallery.count }
    private var current: Int { min(max(page ?? 0, 0), max(count - 1, 0)) }

    var body: some View {
        GeometryReader { geo in
            let limit = max(160, geo.size.width - 48)
            let widths = (0..<count).map { min(limit, (height * ratio($0)).rounded()) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        slide(index)
                            .frame(width: widths[index], height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.leading, max(0, (geo.size.width - (widths.first ?? 0)) / 2), for: .scrollContent)
            .contentMargins(.trailing, max(0, (geo.size.width - (widths.last ?? 0)) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .scrollDisabled(count < 2)
            .overlay(alignment: .trailing) {
                if current + 1 < count {
                    chevron("chevron.right", label: "Próxima imagem") { move(1) }
                        .padding(.trailing, chevronInset)
                }
            }
            .overlay(alignment: .leading) {
                if current > 0 {
                    chevron("chevron.left", label: "Imagem anterior") { move(-1) }
                        .padding(.leading, chevronInset)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(count > 1 ? "Carrossel de \(count) mídias" : reference.displayTitle)
        .accessibilityValue(count > 1 ? "\(current + 1) de \(count)" : "")
        .accessibilityIdentifier(count > 1 ? "post.carousel" : "post.photo")
    }

    private func ratio(_ index: Int) -> CGFloat {
        if isVideo, let media = reference.media, let width = media.width, let height = media.height,
           width > 0, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        guard reference.gallery.indices.contains(index) else { return 0.75 }
        let info = reference.gallery[index]
        guard info.width > 0, info.height > 0 else { return 0.75 }
        return CGFloat(info.width) / CGFloat(info.height)
    }

    private func move(_ delta: Int) {
        withAnimation(.snappy(duration: 0.3)) { page = min(max(current + delta, 0), count - 1) }
    }

    @ViewBuilder private func slide(_ index: Int) -> some View {
        ZStack {
            GalleryStyle.fill
            if isVideo {
                if reference.media?.loop == true {
                    ZStack {
                        RemoteImage(reference: reference, thumbnail: true, fill: true)
                        MotionLoop(reference: reference, active: true)
                    }
                } else if let player {
                    VideoPlayer(player: player)
                } else {
                    RemoteImage(reference: reference, thumbnail: true, fill: true)
                    ProgressView().controlSize(.small)
                }
            } else if reference.gallery.indices.contains(index),
                      reference.gallery[index].isVideoPreview,
                      reference.gallery[index].motion != true {
                PreviewClip(reference: reference, index: index)
            } else {
                RemoteImage(reference: reference, thumbnail: true, fill: true, index: index)
                if abs(index - current) <= 1 {
                    RemoteImage(reference: reference, fill: true, index: index, quiet: true)
                }
                if reference.gallery.indices.contains(index),
                   reference.gallery[index].motion == true,
                   index == current {
                    MotionLoop(reference: reference, index: index, active: true)
                }
            }
        }
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GalleryStyle.ink)
                .frame(width: 40, height: 40)
                .background(chevronFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
