import Foundation
import Testing
@testable import QueepCore

@Test func missingFlagReturnsNilWhenReloadRunsOffTheMainThread() {
    let shown = FeatureFlagLoad.current(
        cached: nil as String?,
        reload: { completion in
            DispatchQueue.global(qos: .utility).sync {
                completion()
            }
        },
        read: { nil },
        update: { (_: String) in
            Issue.record("a missing flag must leave the default in place")
        }
    )
    #expect(shown == nil)
}

@Test func cachedVariantReturnsImmediatelyAndUpdatesOnTheMainActor() async {
    let delivery = FlagDelivery()
    let shown = FeatureFlagLoad.current(
        cached: "a",
        reload: { completion in
            DispatchQueue.global(qos: .utility).sync {
                completion()
            }
        },
        read: { "e" },
        update: { fresh in
            #expect(Thread.isMainThread)
            delivery.finish(fresh)
        }
    )
    #expect(shown == "a")
    let updated = await withCheckedContinuation { delivery.setContinuation($0) }
    #expect(updated == "e")
}

/// Holds a flag value that may arrive before or after the test starts waiting.
private final class FlagDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var continuation: CheckedContinuation<String, Never>?

    func finish(_ value: String) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        self.value = value
        lock.unlock()
    }

    func setContinuation(_ continuation: CheckedContinuation<String, Never>) {
        lock.lock()
        if let value {
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }
}
