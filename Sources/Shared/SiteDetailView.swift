import SwiftUI
import QueepCore

/// Opened website: favicon, product name, URL, og:image, AI title, tags. No notes or editor.
struct SiteDetailView: View {
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

    private var productName: String {
        if let name = live.source?.title, !name.isEmpty { return name }
        if let host = live.url.flatMap({ URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }) {
            return host
        }
        return "Site"
    }

    private var functionalTitle: String {
        let value = live.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        if value.caseInsensitiveCompare(productName) == .orderedSame { return "" }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DocumentActions { moreMenu }
                    header
                    if !live.gallery.isEmpty {
                        RemoteImage(reference: live, thumbnail: false, fill: false)
                            .overlay {
                                if live.gallery.first?.motion == true {
                                    MotionLoop(reference: live, fill: false, active: true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if !functionalTitle.isEmpty {
                        Text(functionalTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("site.title")
                    }
                    actions
                    tags
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Theme.danger)
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
            .navigationTitle("Site")
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
            .confirmationDialog("Excluir permanentemente este site?", isPresented: $confirmDelete,
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
                PostBrandMark(surface: .website, size: 40, radius: 8)
                    .padding(.trailing, -12)
                SiteFavicon(reference: live, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(productName)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if let source = live.url {
                    Text(source)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([productName, live.url].compactMap { $0 }.joined(separator: " "))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = live.url, let destination = URL(string: source) {
                Button("Abrir no navegador", systemImage: "safari") { openURL(destination) }
                    .accessibilityIdentifier("site.openOriginal")
                Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
                    .accessibilityIdentifier("site.copyLink")
            }
            Button(live.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: live.isArchived ? "archivebox.fill" : "archivebox") { archive() }
                .accessibilityIdentifier("site.archive")
                .accessibilityValue(live.isArchived ? "Arquivado" : "")
            ReferenceSpaceButton(reference: reference)
                .accessibilityIdentifier("site.space")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var tags: some View {
        let analysis = live.analysis
        let items = Array(((analysis?.topics ?? []) + (analysis?.usefulness ?? [])
                           + (analysis?.entities ?? [])).prefix(10))
        if live.status == "queued" || live.status == "processing" {
            Label("A interpretação acontece em segundo plano. Você já pode fechar este site.",
                  systemImage: "sparkles")
                .font(.callout).foregroundStyle(Theme.inkSoft)
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
            .accessibilityIdentifier("site.retry")
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
                .accessibilityIdentifier("site.archive")
            ReferenceSpaceButton(reference: reference)
            Divider()
            Button("Excluir site", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .disabled(busy).accessibilityIdentifier("site.delete")
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
        } catch { self.error = AnalysisRetry.failureCopy(error) }
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
