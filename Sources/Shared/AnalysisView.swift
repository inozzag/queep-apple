import SwiftUI
import QueepCore

/// One poll loop for every analysis screen: interval, cap, terminal status, and a network error
/// that must not leave the UI on "Analisando" with the task already finished.
@MainActor
enum AnalysisPolling {
    static func run(
        policy: AnalysisPoll.Policy,
        interval: Duration,
        fetch: () async throws -> Reference,
        apply: (Reference) -> Void,
        onFailure: (String) -> Void
    ) async {
        var snapshot = AnalysisPoll.Snapshot()
        while !Task.isCancelled {
            let outcome: AnalysisPoll.Outcome
            do {
                let fresh = try await fetch()
                if Task.isCancelled { return }
                apply(fresh)
                let step = AnalysisPoll.afterFetch(
                    status: fresh.status,
                    galleryEmpty: fresh.gallery.isEmpty,
                    mediaIncomplete: fresh.mediaIncomplete == true,
                    snapshot: snapshot,
                    policy: policy
                )
                snapshot = step.0
                outcome = step.1
            } catch is CancellationError {
                return
            } catch {
                let step = AnalysisPoll.afterNetworkError(
                    error.localizedDescription,
                    snapshot: snapshot,
                    policy: policy
                )
                snapshot = step.0
                outcome = step.1
            }
            switch outcome {
            case .keepPolling:
                do { try await Task.sleep(for: interval) } catch { return }
            case .stop:
                return
            case .failed(let message):
                onFailure(message)
                return
            }
        }
    }
}

/// Shown when a poll stops on a connection error while analysis is still queued.
struct AnalysisPollFailure: View {
    let message: String
    var canPollAgain = false
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            if canPollAgain {
                Button("Tentar novamente", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analysis.pollRetry")
            }
        }
    }
}

/// What the AI understood, kept quiet: a summary, a few tags, details on demand.
struct AnalysisView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    let reference: Reference
    @State private var updated: Reference?
    @State private var error: String?
    @State private var busy = false
    @State private var pollEpoch = 0

    private var current: Reference { updated ?? reference }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Sparkle()
                Text("O que o Queep entendeu").font(.headline)
                Spacer()
                StatusPill(status: current.status, partial: current.analysis?.coverage == "partial")
            }
            if let analysis = current.analysis, current.status == "ready" {
                Text(analysis.summary).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let tags = Array((analysis.topics + analysis.usefulness + analysis.entities).prefix(8))
                if !tags.isEmpty { FlowChips(items: tags) }
                ForEach(Array(analysis.limitations.enumerated()), id: \.offset) { _, limitation in
                    Label(limitation, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if current.status == "queued" || current.status == "processing" {
                Text("A interpretação acontece em segundo plano. Você já pode fechar esta referência.")
                    .font(.callout).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if let source = current.source {
                Divider()
                Label(source.state == "read" ? sourceReadLabel(source) : "Página indisponível",
                      systemImage: source.state == "read" ? "doc.text" : "exclamationmark.circle")
                    .font(.callout)
                    .accessibilityIdentifier("source.status")
                if source.state == "read" {
                    DisclosureGroup("Ver texto lido") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !source.title.isEmpty { Text(source.title).font(.headline) }
                            Text(source.text).font(.callout).textSelection(.enabled)
                                .accessibilityIdentifier("source.text")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.font(.callout)
                }
                HStack(spacing: 12) {
                    Text(source.fetchedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                    if source.url != current.url, let url = URL(string: source.url),
                       ["https", "http"].contains(url.scheme ?? "") {
                        Link("Abrir página de destino", destination: url).font(.caption)
                    }
                }
            }
            if current.media != nil, let transcript = current.transcript, !transcript.isEmpty {
                Divider()
                DisclosureGroup("Transcrição automática") {
                    Text(transcript).font(.callout).textSelection(.enabled).padding(.top, 6)
                        .accessibilityIdentifier("media.transcript")
                }.font(.callout).accessibilityIdentifier("media.showTranscript")
            }
            if current.showsAnalysisRetry {
                Button("Tentar análise novamente", systemImage: "arrow.clockwise") {
                    Task { await retry() }
                }.buttonStyle(.bordered).disabled(busy)
            }
            if let error {
                AnalysisPollFailure(
                    message: error,
                    canPollAgain: current.status == "queued" || current.status == "processing"
                ) {
                    self.error = nil
                    pollEpoch += 1
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18, elevated: false)
        .task(id: "\(session.userID ?? "")/\(reference.id)/\(pollEpoch)") {
            guard let uid = session.userID else { return }
            await AnalysisPolling.run(
                policy: .analysis,
                interval: .seconds(5),
                fetch: {
                    guard let api = session.client(), session.userID == uid else { throw CancellationError() }
                    return try await api.get(id: reference.id)
                },
                apply: { value in
                    updated = value
                    store.adopt(value)
                    error = nil
                },
                onFailure: { error = $0 }
            )
        }
    }

    private func retry() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let value = try await api.retryAnalysis(current)
            guard session.userID == uid else { return }
            updated = value
            store.adopt(value)
            if AnalysisPoll.resumes(afterRetry: value.status) {
                pollEpoch += 1
            }
        } catch {
            self.error = AnalysisRetry.failureCopy(error)
        }
    }

    private func sourceReadLabel(_ source: SourceContent) -> String {
        if current.linkSurface?.isPost == true { return "Texto do post lido" }
        if source.contentKind == "metadata" { return "Informações públicas lidas" }
        return "Texto da página lido"
    }
}

/// Chips that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in Chip(text: item) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
