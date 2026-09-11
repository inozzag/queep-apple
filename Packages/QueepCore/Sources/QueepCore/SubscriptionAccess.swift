import Foundation

public struct SubscriptionAccess: Decodable, Sendable {
    public let mode: String
    public let active: Bool
    public let expiresAt: Date?
    public let willRenew: Bool
    public let checkedAt: Date

    public var isDevelopment: Bool { mode == "development" }
}
