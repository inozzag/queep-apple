import Foundation

public struct AccountStatus: Decodable, Sendable {
    public let status: String
    public let version: Int
    public let deleteAt: Date?
    public let canRestore: Bool
    public var isActive: Bool { status == "active" }
}
