import Foundation

/// When the library list should be fetched again, and what an in-flight card should say.
public enum LibrarySync {
    /// Refresh while analysis is still running, or while a reference detail is open
    /// (carousel photos can arrive after the status is already ready). Item count is not a gate.
    public static func shouldRefresh(statuses: [String], detailOpen: Bool) -> Bool {
        if detailOpen { return true }
        return statuses.contains { $0 == "queued" || $0 == "processing" }
    }

    /// The upload has already finished. The tile is waiting on analysis.
    public static func analyzingTile(_ status: String) -> String? {
        switch status {
        case "queued": "Aguardando análise…"
        case "processing": "Analisando…"
        default: nil
        }
    }
}
