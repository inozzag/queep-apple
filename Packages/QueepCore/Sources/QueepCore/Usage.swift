import Foundation

public struct UsageCounter: Decodable, Sendable {
    public let used: Int
    public let limit: Int
}

public struct Usage: Decodable, Sendable {
    public let resetsAt: Date
    public let counters: [String: UsageCounter]
}
