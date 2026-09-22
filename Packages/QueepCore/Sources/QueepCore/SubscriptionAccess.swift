import Foundation

public enum SubscriptionPlan: String, Decodable, Sendable, CaseIterable {
    case free, pro, max
    public var title: String { self == .free ? "Free" : self == .pro ? "Pro" : "Max" }
    public var rank: Int { self == .free ? 0 : self == .pro ? 1 : 2 }

    public static func product(_ identifier: String) -> SubscriptionPlan? {
        switch identifier {
        case "app.queep.pro.monthly", "app.queep.pro.yearly",
             "app.queep.mac.pro.monthly", "app.queep.mac.pro.yearly": .pro
        case "app.queep.max.monthly", "app.queep.max.yearly",
             "app.queep.mac.max.monthly", "app.queep.mac.max.yearly": .max
        default: nil
        }
    }
}

public struct SubscriptionFeatures: Decodable, Sendable {
    public let spaces: Bool
    public let mediaAv: Bool
}

public struct SubscriptionAccess: Decodable, Sendable {
    public let mode: String
    public let active: Bool
    public let expiresAt: Date?
    public let willRenew: Bool
    public let checkedAt: Date
    public let plan: SubscriptionPlan
    public let features: SubscriptionFeatures
    public let limits: [String: Int]

    public var isDevelopment: Bool { mode == "development" }
}

public struct PlanRequirement: Decodable, Sendable, Identifiable {
    public var id: String { "\(code)-\(resource)-\(plan.rawValue)" }
    public let code: String
    public let message: String
    public let plan: SubscriptionPlan
    public let resource: String
    public let requiredPlan: SubscriptionPlan?
    public let resetsAt: Date?

    public static func media(for plan: SubscriptionPlan) -> Self {
        Self(code: "media_av_required", message: "Áudio e vídeo são do Queep Max.",
             plan: plan, resource: "media_av", requiredPlan: .max, resetsAt: nil)
    }
}
