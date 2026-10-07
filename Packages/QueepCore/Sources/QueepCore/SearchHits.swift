import Foundation

/// Search hits survive a library refresh. A newer revision or a status that is not ready
/// updates the hit; it does not remove it. Hits absent from this page stay as they are.
public enum SearchHits {
    public static func updated(_ hits: [Reference], with fresh: [Reference]) -> [Reference] {
        let byID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        return hits.map { byID[$0.id] ?? $0 }
    }
}
