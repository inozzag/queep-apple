import SwiftUI
import QueepCore

struct AnalysisView: View {
    @Environment(Session.self) private var session
    let reference: Reference
    @State private var updated: Reference?
    @State private var error: String?
    @State private var busy = false

    private var current: Reference { updated ?? reference }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.statusLabel).font(.caption).foregroundStyle(.secondary)
            if let analysis = current.analysis, current.status == "ready" {
                Text(analysis.summary).font(.callout).textSelection(.enabled)
                ForEach(Array(analysis.limitations.enumerated()), id: \.offset) { _, limitation in
                    Text(limitation).font(.caption).foregroundStyle(.secondary)
                }
            }
            if current.status == "error" {
                Button("Tentar análise novamente") {
                    Task {
                        guard let api = session.client(), let uid = session.userID else { return }
                        busy = true; error = nil
                        defer { busy = false }
                        do {
                            let value = try await api.retryAnalysis(current)
                            guard session.userID == uid else { return }
                            updated = value
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(session.userID ?? "")/\(reference.id)/\(current.status)") {
            guard let api = session.client(), let uid = session.userID else { return }
            // Also refresh once on opening: search cards may outlive a processing update.
            repeat {
                do {
                    let value = try await api.get(id: reference.id)
                    guard !Task.isCancelled, session.userID == uid else { return }
                    updated = value
                    if value.status == "ready" || value.status == "error" { return }
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError { return }
                catch { return }
            } while !Task.isCancelled
        }
    }
}
