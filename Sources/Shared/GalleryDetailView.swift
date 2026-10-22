import AVKit
import SwiftUI
import QueepCore

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
    /// A short header over the media, so the media gets the window: title and text, the topics,
    /// then the source and the actions on one line. Esc and Anterior/Próximo sit in the corners.
    private func desktop(_ size: CGSize) -> some View {
        let column = min(760, max(380, size.width - 440))
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                    .frame(width: column)
                    .padding(.top, 22)
                GeometryReader { box in
                    VStack(spacing: 14) {
                        slides(height: max(240, box.size.height - 20), spacing: 48, chevronInset: 28,
                               chevronFill: Theme.surface)
                        dots
                    }
                    .frame(width: box.size.width, height: box.size.height)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 20)
            }
            HStack(alignment: .center, spacing: 8) {
                Button(action: close) { GalleryPill(title: "Esc", leading: "ri-close-line", height: 36) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("gallery.close")
                Spacer()
                navButton(previous: true)
                navButton(previous: false)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleText
            if !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            topicsRow.padding(.top, 12)
            transcriptText
            analysisStatus.padding(.top, 10)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 14)
            HStack(spacing: 8) {
                source
                Spacer(minLength: 16)
                moreMenu(height: actionHeight)
                shareButton(stretches: false)
                originalButton(stretches: false)
            }
            .padding(.top, 12)
            if error != nil { errorText.padding(.top, 10) }
        }
    }
    #else
    private func phone(_ size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 12) {
                    slides(height: min(460, max(240, size.height * 0.42)), spacing: 12, chevronInset: 14,
                           chevronFill: Theme.surface.opacity(0.9))
                    dots
                }
                .padding(.vertical, 16)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.top, 8)
                HStack(spacing: 8) {
                    Button(action: close) { GalleryPill(leading: "ri-close-line", height: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fechar")
                        .accessibilityIdentifier("gallery.close")
                    Spacer()
                    moreMenu(height: 44)
                    navButton(previous: true)
                    navButton(previous: false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                VStack(alignment: .leading, spacing: 12) {
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                    titleText
                    if !summary.isEmpty { summaryText }
                    analysisExtras
                    analysisStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                Rectangle().fill(Theme.line).frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                source
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                VStack(spacing: 8) {
                    shareButton(stretches: true)
                    originalButton(stretches: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                if error != nil { errorText.padding(.horizontal, 16).padding(.top, 12) }
            }
            .padding(.bottom, 32)
        }
    }
    #endif

    private var titleText: some View {
        Text(title)
            .font(.system(size: titleSize, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("gallery.title")
    }

    private var titleSize: CGFloat {
        #if os(macOS)
        return 18
        #else
        return 20
        #endif
    }

    @ViewBuilder private var analysisStatus: some View {
        #if os(macOS)
        if current.galleryStatusLine != nil || (current.showsAnalysisRetry && !busy) {
            HStack(alignment: .center, spacing: 12) {
                if let line = current.galleryStatusLine {
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gallery.status")
                }
                Spacer(minLength: 0)
                if current.showsAnalysisRetry && !busy {
                    Button {
                        Task { await retryAnalysis() }
                    } label: {
                        GalleryPill(title: "Analisar de novo", leading: "ri-refresh-line", height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery.retry")
                }
            }
        }
        #else
        if current.galleryStatusLine != nil || (current.showsAnalysisRetry && !busy) {
            VStack(alignment: .leading, spacing: 8) {
                if let line = current.galleryStatusLine {
                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(current.status == "queued" || current.status == "processing"
                                         ? Theme.inkSoft : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gallery.status")
                }
                if current.showsAnalysisRetry && !busy {
                    Button {
                        Task { await retryAnalysis() }
                    } label: {
                        GalleryPill(title: "Analisar de novo", leading: "ri-refresh-line")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }        #endif
    }


    private var summaryText: some View {
        Text(summary)
            .font(.system(size: 16))
            .foregroundStyle(Theme.ink)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Where it came from: the network or kind in a 60pt tile, then the author.
    private var source: some View {
        HStack(spacing: sourceTile < 48 ? 10 : 14) {
            // The badge already carries the network's mark beside the avatar.
            if !(authorName != nil && current.authorImage != nil) {
                ChromeIcon(asset: sourceIcon, size: sourceTile, icon: sourceTile < 48 ? 18 : 24)
                    .accessibilityHidden(true)
            }
            if let authorName {
                HStack(spacing: 8) {
                    if current.authorImage != nil {
                        SourceBadge(reference: current, size: 26)
                    }
                    Text(authorName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            } else {
                Text(tag)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceTile: CGFloat {
        #if os(macOS)
        return actionHeight
        #else
        return 48
        #endif
    }

    private var sourceIcon: String {
        switch current.linkSurface {
        case .twitter: return "ri-twitter-x-fill"
        case .instagram: return "ri-instagram-fill"
        case .dribbble: return "ri-dribbble-line"
        case .behance: return "ri-behance-fill"
        case .pinterest: return "ri-pinterest-fill"
        case .medium: return "ri-medium-fill"
        case .website: return "ri-global-line"
        case .none: break
        }
        switch current.kind {
        case "image": return "ri-image-line"
        case "note": return "ri-sticky-note-line"
        case "audio": return "ri-voiceprint-line"
        case "video": return "ri-video-line"
        default: return "ri-link"
        }
    }

    private var errorText: some View {
        HStack(spacing: 8) {
            QueepIcon("ri-error-warning-line", size: 18, color: Theme.danger)
            Text(error ?? "")
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Theme.danger)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(slideCount, 1), id: \.self) { index in
                Circle()
                    .fill(index == slide ? Theme.ink : Theme.lineStrong)
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
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
        topicsRow
        transcriptText
    }

    @ViewBuilder private var topicsRow: some View {
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
    }

    @ViewBuilder private var transcriptText: some View {
        if let transcript = current.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
            Text("Transcrição")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
            Text(transcript)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(4)
                #if os(macOS)
                .lineLimit(3)
                #endif
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
                        leading: isPrevious ? "ri-arrow-left-s-line" : nil,
                        trailing: isPrevious ? nil : "ri-arrow-right-s-line", height: 36)
            #else
            GalleryPill(leading: isPrevious ? "ri-arrow-left-s-line" : "ri-arrow-right-s-line", height: 44)
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
            #if os(macOS)
            ChromeIcon(asset: "ri-more-line", size: height, icon: 18)
            #else
            GalleryPill(leading: "ri-more-line", height: height)
            #endif
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
                HStack(spacing: 8) {
                    Text("Compartilhar")
                    QueepIcon("ri-share-2-line", size: actionIcon, color: Theme.ink)
                }
            }
            .buttonStyle(.queep(.neutral, height: actionHeight, stretches: stretches, radius: actionRadius))
            .accessibilityIdentifier("gallery.share")
        }
    }

    @ViewBuilder private func originalButton(stretches: Bool) -> some View {
        if let originalURL {
            Button { openURL(originalURL) } label: {
                HStack(spacing: 8) {
                    Text("Ver original")
                    QueepIcon("ri-arrow-right-up-box-line", size: actionIcon, color: Theme.onAction)
                }
            }
            .buttonStyle(.queep(.dark, height: actionHeight, stretches: stretches, radius: actionRadius))
            .accessibilityIdentifier("post.openOriginal")
        } else if canEdit {
            Button { editing = current } label: {
                HStack(spacing: 8) {
                    Text("Editar")
                    QueepIcon("ri-edit-line", size: 22, color: Theme.onAction)
                }
            }
            .buttonStyle(.queep(.dark, height: actionHeight, stretches: stretches, radius: actionRadius))
            .accessibilityIdentifier("gallery.edit.open")
        }
    }

    /// Compact on the Mac, like the library's bar; the iPhone keeps 48pt full-width buttons.
    private var actionHeight: CGFloat {
        #if os(macOS)
        return ChromeMetrics.compact.control
        #else
        return 48
        #endif
    }

    private var actionIcon: CGFloat {
        #if os(macOS)
        return 18
        #else
        return 24
        #endif
    }

    private var actionRadius: CGFloat {
        #if os(macOS)
        return ChromeMetrics.compact.controlRadius
        #else
        return Theme.controlRadius
        #endif
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
            let opened = AVPlayer(url: temporary.url)
            player = opened
            if video { opened.play() }
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
                Button { dismiss() } label: { GalleryPill(title: "Fechar", leading: "ri-close-line") }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityIdentifier("gallery.edit.close")
                Spacer()
                Text("Editar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            TextField("Título", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...3)
                .accessibilityLabel("Título")
                .accessibilityIdentifier("gallery.edit.title")
            Text("Notas")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .accessibilityLabel("Notas")
                .accessibilityIdentifier("gallery.edit.text")
            if trimmedTitle.count > 200 {
                Text("O título tem no máximo 200 caracteres.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)
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

/// A post's full video with its sound, stored on Pro and Max. The poster shows while it loads;
/// it plays while it is the slide on screen. If the video cannot be read, the muted loop stands in.
private struct PostVideo: View {
    @Environment(Session.self) private var session
    let reference: Reference
    let index: Int
    var active = true
    @State private var player: AVPlayer?
    @State private var file: TemporaryMediaFile?
    @State private var failed = false

    var body: some View {
        ZStack {
            RemoteImage(reference: reference, thumbnail: true, fill: true, index: index)
            if let player {
                VideoPlayer(player: player)
            } else if failed {
                MotionLoop(reference: reference, index: index, active: active, cornerRadius: 12)
            } else if active {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: "\(reference.id)/\(index)/\(active)") {
            if active { await load() } else { player?.pause() }
        }
        .onDisappear { clear() }
    }

    private func load() async {
        if let player {
            player.play()
            return
        }
        guard let api = session.client(), let owner = session.userID else { return }
        do {
            let data = try await api.imageData(reference, index: index, role: "clip")
            guard !Task.isCancelled, owner == session.userID, !data.isEmpty else { return }
            let temporary = TemporaryMediaFile(extension: "mp4")
            try data.write(to: temporary.url, options: .atomic)
            file = temporary
            let opened = AVPlayer(url: temporary.url)
            player = opened
            opened.play()
        } catch is CancellationError {
        } catch {
            failed = true
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
                    chevron("ri-arrow-right-s-line", label: "Próxima imagem") { move(1) }
                        .padding(.trailing, chevronInset)
                }
            }
            .overlay(alignment: .leading) {
                if current > 0 {
                    chevron("ri-arrow-left-s-line", label: "Imagem anterior") { move(-1) }
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
            Theme.fill
            if isVideo {
                if reference.media?.loop == true {
                    ZStack {
                        RemoteImage(reference: reference, thumbnail: true, fill: true)
                        MotionLoop(reference: reference, active: true, cornerRadius: 12)
                    }
                } else if let player {
                    VideoPlayer(player: player)
                } else {
                    RemoteImage(reference: reference, thumbnail: true, fill: true)
                    ProgressView().controlSize(.small)
                }
            } else if reference.gallery.indices.contains(index), reference.gallery[index].clip == true {
                PostVideo(reference: reference, index: index, active: index == current)
            } else {
                RemoteImage(reference: reference, thumbnail: true, fill: true, index: index)
                if abs(index - current) <= 1 {
                    RemoteImage(reference: reference, fill: true, index: index, quiet: true)
                }
                if reference.gallery.indices.contains(index),
                   reference.gallery[index].motion == true,
                   index == current {
                    MotionLoop(reference: reference, index: index, active: true, cornerRadius: 12)
                }
            }
        }
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            QueepIcon(symbol, size: 22, color: Theme.ink)
                .frame(width: 40, height: 40)
                .background(chevronFill, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
