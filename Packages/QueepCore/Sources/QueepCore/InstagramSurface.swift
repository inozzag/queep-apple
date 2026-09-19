import Foundation

extension LinkSurface {
    /// Shortcode from /p|/reel|/reels|/tv, /user/p|reel/code, or /share/p|reel/hash.
    public static func instagramPostCode(url: String?) -> String? {
        guard identify(url: url) == .instagram, let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        let roots: Set<String> = ["p", "reel", "reels", "tv"]
        if parts.count >= 2, roots.contains(parts[0].lowercased()) {
            return validInstagramCode(parts[1])
        }
        if parts.count >= 3, roots.contains(parts[1].lowercased()) {
            return validInstagramCode(parts[2])
        }
        if parts.count >= 3, parts[0].lowercased() == "share", roots.contains(parts[1].lowercased()) {
            return validInstagramCode(parts[2])
        }
        return nil
    }

    /// Public handle from instagram.com/name; never p/reel/stories/explore/share.
    public static func instagramProfileHandle(url: String?) -> String? {
        guard identify(url: url) == .instagram, instagramPostCode(url: url) == nil else { return nil }
        guard let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        let handle = parts[0]
        let reserved: Set<String> = [
            "p", "reel", "reels", "tv", "stories", "explore", "accounts", "direct",
            "about", "legal", "developer", "developers", "privacy", "help", "api", "share"
        ]
        guard !reserved.contains(handle.lowercased()) else { return nil }
        guard handle.range(of: "^[A-Za-z0-9._]{1,30}$", options: .regularExpression) != nil else {
            return nil
        }
        return handle
    }

    private static func validInstagramCode(_ value: String) -> String? {
        value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) == nil ? nil : value
    }
}
