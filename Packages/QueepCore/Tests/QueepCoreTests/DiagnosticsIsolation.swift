import Foundation

/// `APIDiagnostics.record` is process-wide. Tests that set it or emit a report must share this actor.
actor DiagnosticsIsolation {
    static let shared = DiagnosticsIsolation()

    func perform<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        try await work()
    }
}
