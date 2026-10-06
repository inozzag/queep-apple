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

/// Whether the first-save sheet can be shown, and whether that attempt should be remembered.
public enum FirstPaywallDecision: Equatable, Sendable {
    /// Offers or the account's plan are still unknown. Try again later.
    case wait
    /// A known paying subscriber does not get the first-save sheet.
    case skip
    /// The account is Free, or this is a development session that should preview the sheet.
    case show

    /// Remember the sheet only after a decision that no longer depends on a later load.
    public var rememberShown: Bool { self != .wait }
}

public enum FirstPaywall {
    /// Unknown access is not Free. A failed load must not suppress the sheet permanently.
    public static func decide(offersLoaded: Bool, access: SubscriptionAccess?) -> FirstPaywallDecision {
        guard offersLoaded, let access else { return .wait }
        if access.plan == .free || access.isDevelopment { return .show }
        return .skip
    }
}
