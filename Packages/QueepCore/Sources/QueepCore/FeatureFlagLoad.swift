import Foundation

/// Reads a cached feature-flag value without waiting on the reload callback.
///
/// The completion passed to `reload` is not isolated to the main actor, so a
/// client such as PostHog can invoke it on its own queue. A value found there
/// is delivered later through `update`, on the main actor. `nil` from `read`
/// leaves the caller on the default it already chose.
public enum FeatureFlagLoad {
    public static func current<Value: Sendable>(
        cached: Value?,
        reload: (_ completion: @escaping @Sendable () -> Void) -> Void,
        read: @escaping @Sendable () -> Value?,
        update: @escaping @MainActor (Value) -> Void
    ) -> Value? {
        let completion: @Sendable () -> Void = {
            guard let fresh = read() else { return }
            Task { @MainActor in
                update(fresh)
            }
        }
        reload(completion)
        return cached
    }
}
