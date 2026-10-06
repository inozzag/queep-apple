import Foundation

/// Where a package button sends an account that already has a subscription.
public enum SubscriptionCheckout {
    /// An active subscriber buys a higher plan in the app. Changing the period of the
    /// current plan, or moving to a lower one, stays in Apple's subscription management.
    public static func managesInAppStore(access: SubscriptionAccess?, packagePlan: SubscriptionPlan?) -> Bool {
        guard let access, access.active, !access.isDevelopment else { return false }
        guard let packagePlan else { return true }
        return packagePlan.rank <= access.plan.rank
    }
}
