import SwiftUI
import QueepCore

/// Opened social profile: avatar, name, handle, bio, tags. No notes, title editor or post gallery.
struct ProfileDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let reference: Reference
    @State private var latest: Reference?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var pollEpoch = 0
    @State private var pollError: String?

    private var live: Reference {
        let fromStore = store.items.first(where: { $0.id == reference.id })
        return [latest, fromStore, reference].compactMap { $0 }.max { $0.updatedAt < $1.updatedAt }
            ?? reference
    }
    private var identity: PostIdentity { PostIdentity(live) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DocumentActions { moreMenu }
                    header
                    if !identity.body.isEmpty {
                        Text(identity.body)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("profile.bio")
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
            .navigationTitle("Perfil")
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
            }
            .confirmationDialog("Excluir permanentemente este perfil?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            } message: { Text("Arquivar esconde. Excluir apaga da sua conta.") }
        }
        .subscriptionGate()
        .interactiveDismissDisabled(busy)
        .task(id: "\(reference.id)/\(pollEpoch)") { await poll() }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 720, minHeight: 480, idealHeight: 640)
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
                    .accessibilityIdentifier("profile.openOriginal")
                Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
                    .accessibilityIdentifier("profile.copyLink")
            }
            Button(live.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: live.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("profile.archive")
                .accessibilityValue(live.isArchived ? "Arquivado" : "")
            ReferenceSpaceButton(reference: reference)
                .accessibilityIdentifier("profile.space")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var tags: some View {
        let analysis = live.analysis
        let items = Array(((analysis?.topics ?? []) + (analysis?.usefulness ?? [])
                           + (analysis?.entities ?? [])).prefix(10))
        if live.status == "queued" || live.status == "processing" {
            Label("A interpretação acontece em segundo plano. Você já pode fechar este perfil.",
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
        if live.showsAnalysisRetry {
            Button("Tentar análise novamente", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            .accessibilityIdentifier("profile.retry")
        }
    }

    private var moreMenu: some View {
        Menu {
            if let source = live.url, let destination = URL(string: source) {
                Button("Abrir no navegador", systemImage: "safari") { openURL(destination) }
                Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
            }
            Button(live.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: live.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("profile.archive")
            ReferenceSpaceButton(reference: reference)
            Divider()
            Button("Excluir perfil", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .disabled(busy).accessibilityIdentifier("profile.delete")
        } label: { Label("Mais", systemImage: "ellipsis.circle") }
            .accessibilityIdentifier("reference.more")
    }

    private func poll() async {
        guard let uid = session.userID else { return }
        await AnalysisPolling.run(
            policy: .detail,
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

    private func archive() {
        guard let api = session.client(), let uid = session.userID else { return }
        store.setArchived([live], archived: !live.isArchived, client: api, account: uid)
    }

    private func remove() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.delete(live)
            guard session.userID == uid else { return }
            store.discardSearchReference(live.id)
            await store.refresh(api, account: uid, force: true)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
