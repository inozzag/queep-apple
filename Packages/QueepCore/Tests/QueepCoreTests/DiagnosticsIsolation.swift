import Foundation

/// `APIDiagnostics.record` is process-wide. Tests that set it or emit a report must share this actor.
/// An actor method yields at `await`, so a bare `await work()` lets the next test replace the hook
/// while the first request is still running. The flag keeps the next caller waiting until `work` returns.
actor DiagnosticsIsolation {
    static let shared = DiagnosticsIsolation()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        await lock()
        defer { unlock() }
        return try await work()
    }

    private func lock() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func unlock() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
