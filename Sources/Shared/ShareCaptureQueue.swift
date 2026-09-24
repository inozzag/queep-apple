import Foundation
import QueepCore
import Security

/// Ids saved by the share extension. The extension does not send analytics; the app does, after the reference exists.
enum ShareCaptureQueue {
    struct Item: Codable, Equatable, Sendable {
        var id: String
        var kind: String
    }

    private static let service = "app.queep.share-captures"
    private static let account = "pending"

    static func enqueue(id: String, kind: String) {
        guard ProductEvent.kinds.contains(kind), isCaptureID(id) else { return }
        var items = load()
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(Item(id: id, kind: kind))
        if items.count > 30 { items.removeFirst(items.count - 30) }
        store(items)
    }

    static func load() -> [Item] {
        guard let group = accessGroup, let data = read(group: group) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    static func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        store(load().filter { !ids.contains($0.id) })
    }

    private static func isCaptureID(_ id: String) -> Bool {
        (8...80).contains(id.count) && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static var accessGroup: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "QueepAuthGroup") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty, !raw.contains("$(") else { return nil }
        return raw
    }

    private static func store(_ items: [Item]) {
        guard let group = accessGroup, let data = try? JSONEncoder().encode(items) else { return }
        delete(group: group)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(group: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(group: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group
        ]
        SecItemDelete(query as CFDictionary)
    }
}
