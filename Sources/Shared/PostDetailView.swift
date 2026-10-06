import AVKit
import SwiftUI
import QueepCore

/// Opened social post: gallery, author, caption, editable title, tags. No notes or AI prose.
struct PostDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    let reference: Reference
    @State private var title: String
    @State private var latest: Reference?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var mutationID = UUID()
    @State private var player: AVPlayer?
    @State private var file: TemporaryMediaFile?
    @State private var mediaError: String?
    @State private var mediaAttempt = 0
    @State private var pollEpoch = 0
    @State private var pollError: String?

    init(reference: Reference) {
        self.reference = reference
        _title = State(initialValue: reference.title)
    }

    private var live: Reference {
        let fromStore = store.items.first(where: { $0.id == reference.id })
        return [latest, fromStore, reference].compactMap { $0 }.max { lhs, rhs in
            if lhs.gallery.count != rhs.gallery.count { return lhs.gallery.count < rhs.gallery.count }
            return lhs.updatedAt < rhs.updatedAt
        } ?? reference
    }
    private var identity: PostIdentity { PostIdentity(live) }
    private var changed: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != live.title
    }
    private var canSave: Bool { changed && !busy && !live.isArchived && title.count <= 200 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DocumentActions { moreMenu }
                    header
                    if !live.gallery.isEmpty {
                        RemoteImageCarousel(reference: live, thumbnail: false, fill: false, height: 360)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if live.media != nil {
                        audioPlayer
                    }
                    if !identity.body.isEmpty {
                        Text(identity.body)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("post.body")
                    }
                    DocumentTitleField(title: $title, disabled: busy || live.isArchived, identifier: "post.title")
                    if title.count > 200 {
                        Text("O título tem no máximo 200 caracteres.").font(.caption).foregroundStyle(.orange)
                    }
                    actions
                    tags
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                    }
                    if let pollError {
                        AnalysisPollFailure(
                            message: pollError,
                            canPollAgain: live.status == "queued" || live.status == "processing"
                        ) {
                            self.pollError = nil
                            pollEpoch += 1
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Color.card)
            .navigationTitle("Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }.disabled(busy)
                        .keyboardShortcut(.cancelAction)
                        #if os(iOS)
                        .labelStyle(.iconOnly)
                        #endif
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { moreMenu }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) }
                        else {
                            #if os(iOS)
                            Label("Salvar", systemImage: "checkmark").labelStyle(.iconOnly)
                            #else
                            Text("Salvar")
                            #endif
                        }
                    }.disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("post.save")
                        .accessibilityLabel(busy ? "Salvando" : "Salvar")
                }
            }
            .confirmationDialog("Excluir permanentemente este post?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            } message: { Text("Arquivar esconde. Excluir apaga da sua conta.") }
        }
        .subscriptionGate()
        .interactiveDismissDisabled(busy)
        .task(id: "\(reference.id)/\(pollEpoch)") { await poll() }
        .task(id: "\(session.userID ?? "")/\(live.id)/\(live.media?.sha256 ?? "")/\(mediaAttempt)") {
            await loadAudio()
        }
        .onDisappear { clearAudio() }
        .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 720, minHeight: 560, idealHeight: 720)
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .bottom, spacing: 0) {
                PostBrandMark(surface: live.linkSurface, size: 40, radius: 8)
                    .padding(.trailing, -12)
                PostAvatar(reference: live, initials: identity.initials, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !identity.author.isEmpty {
                    Text(identity.author)
                        .font(.headline)
                        .foregroundStyle(Theme.homeInk)
                        .lineLimit(1)
                }
                if !identity.handle.isEmpty {
                    Text(identity.handle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.homePreview)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([identity.author, identity.handle].filter { !$0.isEmpty }.joined(separator: " "))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = live.url, let destination = URL(string: source) {
                Button("Abrir no navegador", systemImage: "safari") { openURL(destination) }
                    .accessibilityIdentifier("post.openOriginal")
                Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
                    .accessibilityIdentifier("post.copyLink")
            }
            Button(live.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: live.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("post.archive")
                .accessibilityValue(live.isArchived ? "Arquivado" : "")
            ReferenceSpaceButton(reference: reference)
                .accessibilityIdentifier("post.space")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var tags: some View {
        let analysis = live.analysis
        let items = Array(((analysis?.topics ?? []) + (analysis?.usefulness ?? [])
                           + (analysis?.entities ?? []) + (analysis?.appearance ?? [])).prefix(10))
        if live.status == "queued" || live.status == "processing" {
            Label("A interpretação acontece em segundo plano. Você já pode fechar este post.",
                  systemImage: "sparkles")
                .font(.callout).foregroundStyle(Color.muted)
        } else if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Sparkle()
                    Text("Assuntos").font(.headline)
                }
                FlowChips(items: items)
            }
        }
        if live.status == "error" && !live.isArchived {
            Button("Tentar análise novamente", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            .accessibilityIdentifier("post.retry")
        }
    }

    @ViewBuilder private var audioPlayer: some View {
        Group {
            if let player {
                MediaPlaybackView(player: player, video: live.kind == "video",
                                  duration: live.media?.durationSeconds ?? 0)
            } else if let mediaError {
                VStack(spacing: 8) {
                    Label(mediaError, systemImage: "exclamationmark.circle")
                    Button("Tentar novamente") { mediaAttempt += 1 }.disabled(busy)
                }.font(.callout).foregroundStyle(Color.muted).frame(maxWidth: .infinity)
            } else {
                ProgressView("Carregando áudio…").controlSize(.small).frame(maxWidth: .infinity)
            }
        }
        .padding(16).frame(maxWidth: .infinity).card(elevated: false)
    }

    private var moreMenu: some View {
        Menu {
            if let source = live.url, let destination = URL(string: source) {
                Button("Abrir no navegador", systemImage: "safari") { openURL(destination) }
                Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
            }
            Button(live.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: live.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("post.archive")
            ReferenceSpaceButton(reference: reference)
            Divider()
            Button("Excluir post", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .disabled(busy).accessibilityIdentifier("post.delete")
        } label: { Label("Mais", systemImage: "ellipsis.circle") }
            .accessibilityIdentifier("reference.more")
    }

    private func poll() async {
        guard let uid = session.userID else { return }
        await AnalysisPolling.run(
            policy: .post,
            interval: .seconds(2),
            fetch: {
                guard let api = session.client(), session.userID == uid else { throw CancellationError() }
                return try await api.get(id: reference.id)
            },
            apply: { fresh in
                latest = fresh
                store.adopt(fresh)
                pollError = nil
            },
            onFailure: { pollError = $0 }
        )
    }

    private func loadAudio() async {
        clearAudio(); mediaError = nil
        guard live.media != nil, let api = session.client(), let owner = session.userID else { return }
        do {
            let data = try await api.mediaData(live)
            guard !Task.isCancelled, owner == session.userID else { return }
            let temporary = TemporaryMediaFile(extension: live.kind == "video" ? "mp4" : "m4a")
            try data.write(to: temporary.url, options: .atomic)
            file = temporary
            player = AVPlayer(url: temporary.url)
        } catch is CancellationError { }
        catch { if !Task.isCancelled { mediaError = error.localizedDescription } }
    }

    private func clearAudio() {
        player?.pause()
        player = nil
        file = nil
    }

    private func archive() {
        guard let api = session.client(), let uid = session.userID else { return }
        clearAudio()
        store.setArchived([live], archived: !live.isArchived, client: api, account: uid)
    }

    private func save() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let updated = try await api.editMetadata(live, title: title, text: live.text, mutationID: mutationID)
            guard session.userID == uid else { return }
            latest = updated
            store.discardSearchReference(live.id)
            await store.refresh(api, account: uid)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func retry() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await api.retryAnalysis(live)
            guard session.userID == uid else { return }
            latest = value
            store.adopt(value)
            if AnalysisPoll.resumes(afterRetry: value.status) {
                pollEpoch += 1
            }
        } catch { self.error = error.localizedDescription }
    }

    private func remove() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.delete(live)
            guard session.userID == uid else { return }
            clearAudio()
            store.discardSearchReference(live.id)
            await store.refresh(api, account: uid)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
