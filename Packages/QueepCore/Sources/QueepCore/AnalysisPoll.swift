import Foundation

/// Decides whether an analysis poll should sleep, stop, or surface a failure.
/// Views share this so a retry, a terminal status, and a dropped connection behave the same way.
public enum AnalysisPoll {
    public struct Policy: Equatable, Sendable {
        public var maxAttempts: Int
        /// Consecutive transport failures before the poll stops and reports the error.
        public var maxNetworkFailures: Int
        public var waitsForGallery: Bool
        /// Ready responses with an empty gallery to accept before stopping, when `waitsForGallery` is set.
        public var readyGalleryPolls: Int

        public init(maxAttempts: Int, maxNetworkFailures: Int, waitsForGallery: Bool, readyGalleryPolls: Int) {
            self.maxAttempts = maxAttempts
            self.maxNetworkFailures = maxNetworkFailures
            self.waitsForGallery = waitsForGallery
            self.readyGalleryPolls = readyGalleryPolls
        }

        /// Site and profile: stop on ready or error.
        public static let detail = Policy(maxAttempts: 45, maxNetworkFailures: 45, waitsForGallery: false, readyGalleryPolls: 1)
        /// Post: after ready, keep going until carousel photos arrive, with a short extra cap.
        public static let post = Policy(maxAttempts: 45, maxNetworkFailures: 45, waitsForGallery: true, readyGalleryPolls: 15)
        /// Notes, images, and media. A long analysis may keep polling; a dead network surfaces quickly.
        public static let analysis = Policy(maxAttempts: 120, maxNetworkFailures: 3, waitsForGallery: false, readyGalleryPolls: 1)
    }

    public struct Snapshot: Equatable, Sendable {
        public var attempts: Int
        public var readyPolls: Int
        public var consecutiveNetworkFailures: Int

        public init(attempts: Int = 0, readyPolls: Int = 0, consecutiveNetworkFailures: Int = 0) {
            self.attempts = attempts
            self.readyPolls = readyPolls
            self.consecutiveNetworkFailures = consecutiveNetworkFailures
        }
    }

    public enum Outcome: Equatable, Sendable {
        case keepPolling
        case stop
        case failed(String)
    }

    public static func afterFetch(
        status: String,
        galleryEmpty: Bool,
        snapshot: Snapshot,
        policy: Policy
    ) -> (Snapshot, Outcome) {
        var next = snapshot
        next.attempts += 1
        next.consecutiveNetworkFailures = 0
        if status == "error" { return (next, .stop) }
        if status == "ready" {
            next.readyPolls += 1
            let galleryArrived = policy.waitsForGallery && !galleryEmpty
            let galleryWaitOver = !policy.waitsForGallery || next.readyPolls >= policy.readyGalleryPolls
            if galleryArrived || galleryWaitOver { return (next, .stop) }
        }
        if next.attempts >= policy.maxAttempts { return (next, .stop) }
        return (next, .keepPolling)
    }

    /// A dropped connection is not a terminal analysis state. Keep polling until the network cap,
    /// then surface the message so the screen does not stay on "Analisando" with the loop dead.
    public static func afterNetworkError(
        _ message: String,
        snapshot: Snapshot,
        policy: Policy
    ) -> (Snapshot, Outcome) {
        var next = snapshot
        next.attempts += 1
        next.consecutiveNetworkFailures += 1
        if next.consecutiveNetworkFailures >= max(1, policy.maxNetworkFailures) || next.attempts >= policy.maxAttempts {
            return (next, .failed(message))
        }
        return (next, .keepPolling)
    }

    /// Retry puts the analysis back in the queue. Polling has to start again; the reference id did not change.
    public static func resumes(afterRetry status: String) -> Bool {
        status == "queued" || status == "processing"
    }
}
