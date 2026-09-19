import Foundation

extension LinkSurface {
    /// Numeric id from pinterest.com/pin/{id}, or the opaque key from pin.it/{key}.
    public static func pinterestPinId(url: String?) -> String? {
        guard identify(url: url) == .pinterest, let parsed = URL(string: url ?? ""),
              let host = parsed.host?.lowercased() else { return nil }
        let parts = parsed.path.split(separator: "/").map(String.init)
        if host == "pin.it" || host == "www.pin.it" {
            guard parts.count == 1,
                  parts[0].range(
                    of: #"^[A-Za-z0-9_-]{4,64}$"#,
                    options: .regularExpression
                  ) != nil else { return nil }
            return parts[0]
        }
        guard parts.count == 2, parts[0].lowercased() == "pin" else { return nil }
        let segment = parts[1]
        if segment.range(of: #"^[0-9]{6,30}$"#, options: .regularExpression) != nil {
            return segment
        }
        guard segment.range(
            of: #"^.+--[0-9]{6,30}$"#,
            options: .regularExpression
        ) != nil, let identifier = segment.components(separatedBy: "--").last else { return nil }
        return identifier
    }

    /// Creator handle from pinterest.com/{name}; never a Pin, board, or service route.
    public static func pinterestProfileHandle(url: String?) -> String? {
        guard identify(url: url) == .pinterest, pinterestPinId(url: url) == nil,
              let parsed = URL(string: url ?? ""), let host = parsed.host?.lowercased(),
              host != "pin.it", host != "www.pin.it" else { return nil }
        let parts = parsed.path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        let handle = parts[0]
        let reserved: Set<String> = [
            "about", "account", "accounts", "api", "business", "categories", "careers",
            "explore", "help", "ideas", "login", "oauth", "pin", "privacy", "search",
            "settings", "signup", "terms", "today"
        ]
        guard !reserved.contains(handle.lowercased()) else { return nil }
        guard handle.range(
            of: #"^[A-Za-z0-9_]{3,30}$"#,
            options: .regularExpression
        ) != nil, handle.contains(where: { $0.isLetter }) else { return nil }
        return handle
    }
}
