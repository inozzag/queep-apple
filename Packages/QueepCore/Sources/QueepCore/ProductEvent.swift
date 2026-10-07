import Foundation

/// Property bags for the pilot analytics events. Content (note text, URL, query, names) never enters them.
public enum ProductEvent {
    public static let kinds = ["note", "link", "image", "audio", "video", "social"]
    public static let sources = ["library", "shortcut", "share", "drag", "paste"]
    public static let methods = ["apple", "google", "email"]
    public static let paywallReasons = ["plan_limit", "spaces_required", "media_av_required", "storage_limit", "first_save"]

    public static func kind(kind: String, url: String?) -> String {
        switch kind {
        case "image", "audio", "video", "note": return kind
        case "link": return isSocial(url) ? "social" : "link"
        default: return "note"
        }
    }

    public static func captureSaved(kind: String, url: String?, source: String, platform: String) -> [String: String]? {
        guard sources.contains(source), platforms.contains(platform) else { return nil }
        return ["kind": self.kind(kind: kind, url: url), "source": source, "platform": platform]
    }

    public static func auth(created: Bool, method: String, platform: String) -> (name: String, properties: [String: String])? {
        guard methods.contains(method), platforms.contains(platform) else { return nil }
        return (created ? "account_created" : "sign_in_completed", ["method": method, "platform": platform])
    }

    public static func searchSubmitted(hasResults: Bool) -> [String: Bool] {
        ["has_results": hasResults]
    }

    public static func referenceOpened(kind: String, url: String?) -> [String: String] {
        ["kind": self.kind(kind: kind, url: url)]
    }

    public static func spaceCreated(platform: String) -> [String: String]? {
        guard platforms.contains(platform) else { return nil }
        return ["platform": platform]
    }

    public static func paywall(code: String, targetPlan: String?) -> [String: String]? {
        guard paywallReasons.contains(code) else { return nil }
        let target = targetPlan.flatMap { ["pro", "max"].contains($0) ? $0 : nil } ?? "none"
        return ["reason": code, "target_plan": target]
    }

    public static func purchase(plan: String, period: String) -> [String: String]? {
        guard ["pro", "max"].contains(plan), ["month", "year"].contains(period) else { return nil }
        return ["plan": plan, "period": period]
    }

    /// Person properties for PostHog `$identify`. Email and name are included only when Auth already has them.
    /// Blank values are omitted. Capture events do not use this bag.
    public static func person(platform: String, email: String?, name: String?, plan: String?) -> [String: String] {
        var properties: [String: String] = [:]
        if platforms.contains(platform) { properties["platform"] = platform }
        if let email = cleaned(email), email.contains("@"), email.count <= 320 {
            properties["email"] = email
        }
        if let name = cleaned(name), (1...200).contains(name.count) {
            properties["name"] = name
        }
        if let plan, SubscriptionPlan(rawValue: plan) != nil {
            properties["plan"] = plan
        }
        return properties
    }

    public static func billingPeriod(productIdentifier: String) -> String? {
        let id = productIdentifier.lowercased()
        if id.contains("year") { return "year" }
        if id.contains("month") { return "month" }
        return nil
    }

    private static let platforms = ["ios", "macos"]

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isSocial(_ url: String?) -> Bool {
        LinkSurface.twitterHandle(url: url) != nil
            || LinkSurface.twitterProfileHandle(url: url) != nil
            || LinkSurface.instagramPostCode(url: url) != nil
            || LinkSurface.instagramProfileHandle(url: url) != nil
            || LinkSurface.dribbbleShot(url: url) != nil
            || LinkSurface.dribbbleProfileHandle(url: url) != nil
            || LinkSurface.behanceProjectId(url: url) != nil
            || LinkSurface.behanceProfileHandle(url: url) != nil
            || LinkSurface.pinterestPinId(url: url) != nil
            || LinkSurface.pinterestProfileHandle(url: url) != nil
    }
}
