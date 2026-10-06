import Foundation

/// How a saved link should read in the library: a social post, a known site, or a generic page.
public enum LinkSurface: String, Sendable, Equatable {
    case twitter, instagram, dribbble, behance, pinterest, medium, website

    public var brandName: String {
        switch self {
        case .twitter: "X"
        case .instagram: "Instagram"
        case .dribbble: "Dribbble"
        case .behance: "Behance"
        case .pinterest: "Pinterest"
        case .medium: "Medium"
        case .website: "Site"
        }
    }

    /// Posts carry an author and a body; sites are a destination with a host.
    public var isPost: Bool {
        switch self {
        case .twitter, .instagram, .dribbble, .behance, .pinterest: true
        case .medium, .website: false
        }
    }

    /// Public handle from an X/Twitter status URL, if the path is a post.
    public static func twitterHandle(url: String?) -> String? {
        guard identify(url: url) == .twitter, let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[1] == "status" else { return nil }
        let handle = parts[0]
        guard handle != "i", !handle.isEmpty else { return nil }
        return handle
    }

    /// Public handle from x.com/name; never a tweet, i/, search, hashtag or intent.
    public static func twitterProfileHandle(url: String?) -> String? {
        guard identify(url: url) == .twitter, let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        let handle = parts[0]
        let reserved: Set<String> = [
            "i", "intent", "search", "hashtag", "hashtags", "explore", "home", "settings",
            "notifications", "messages", "compose", "login", "signup", "share", "account",
            "web", "status", "privacy", "tos", "download", "about", "help", "oauth", "api"
        ]
        guard !reserved.contains(handle.lowercased()) else { return nil }
        guard handle.range(of: "^[A-Za-z0-9_]{1,15}$", options: .regularExpression) != nil else {
            return nil
        }
        return handle
    }

    /// YouTube and Vimeo keep the video card, not the generic website card.
    public static func isVideoPage(_ url: String?) -> Bool {
        guard let host = URL(string: url ?? "")?.host?.lowercased() else { return false }
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let base = trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
        return base == "youtu.be" || base == "youtube.com" || base.hasSuffix(".youtube.com")
            || base == "vimeo.com" || base.hasSuffix(".vimeo.com")
    }

    public static func identify(url: String?) -> LinkSurface {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return .website }
        return identify(host: host)
    }

    public static func identify(host raw: String) -> LinkSurface {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let base = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if base == "x.com" || base == "twitter.com" || base == "mobile.twitter.com"
            || base.hasSuffix(".twitter.com") || base.hasSuffix(".x.com") {
            return .twitter
        }
        if base == "instagram.com" || base.hasSuffix(".instagram.com") { return .instagram }
        if base == "dribbble.com" || base.hasSuffix(".dribbble.com") { return .dribbble }
        if base == "behance.net" || base.hasSuffix(".behance.net")
            || base == "be.net" { return .behance }
        if base == "pinterest.com" || base.hasSuffix(".pinterest.com")
            || base == "pin.it" { return .pinterest }
        if base == "medium.com" || base.hasSuffix(".medium.com") { return .medium }
        return .website
    }
}

public extension Reference {
    var linkSurface: LinkSurface? {
        guard kind == "link" else { return nil }
        return LinkSurface.identify(url: url)
    }

    var isSocialPost: Bool {
        LinkSurface.twitterHandle(url: url) != nil
            || LinkSurface.instagramPostCode(url: url) != nil
            || LinkSurface.dribbbleShot(url: url) != nil
            || LinkSurface.behanceProjectId(url: url) != nil
            || LinkSurface.pinterestPinId(url: url) != nil
    }

    var isSocialProfile: Bool {
        LinkSurface.twitterProfileHandle(url: url) != nil
            || LinkSurface.instagramProfileHandle(url: url) != nil
            || LinkSurface.dribbbleProfileHandle(url: url) != nil
            || LinkSurface.behanceProfileHandle(url: url) != nil
            || LinkSurface.pinterestProfileHandle(url: url) != nil
    }

    var isWebsite: Bool {
        guard kind == "link", !isSocialPost, !isSocialProfile else { return false }
        if let surface = linkSurface, surface != .website { return false }
        if LinkSurface.isVideoPage(url) { return false }
        return true
    }
}
