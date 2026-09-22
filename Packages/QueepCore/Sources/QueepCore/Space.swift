import Foundation

public struct Space: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var sortIndex: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var referenceCount: Int

    public init(id: String = UUID().uuidString.lowercased(), name: String, sortIndex: Int,
                createdAt: Date = .now, updatedAt: Date = .now, referenceCount: Int = 0) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.referenceCount = referenceCount
    }

    public var countLabel: String {
        "\(referenceCount) \(referenceCount == 1 ? "referência" : "referências")"
    }
}
