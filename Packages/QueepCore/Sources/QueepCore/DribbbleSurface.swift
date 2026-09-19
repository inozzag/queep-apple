import Foundation

extension LinkSurface {
    /// Shot id from dribbble.com/shots/{id}; never a designer profile.
    public static func dribbbleShot(url: String?) -> String? {
        guard identify(url: url) == .dribbble, let path = URL(string: url ?? "")?.path else {
            return nil
        }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "shots" else { return nil }
        let shot = parts[1]
        guard shot.range(
            of: #"^[0-9]{1,20}(?:-[A-Za-z0-9][A-Za-z0-9-]*)?$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return String(shot.prefix { $0.isNumber })
    }

    /// Designer handle from dribbble.com/{name}; never shots/, designers, or search.
    public static func dribbbleProfileHandle(url: String?) -> String? {
        guard identify(url: url) == .dribbble, dribbbleShot(url: url) == nil,
              let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        let handle = parts[0]
        let reserved: Set<String> = [
            "about", "account", "accounts", "advertise", "api", "careers", "collections",
            "contact", "designers", "directories", "explore", "freelancers", "goods",
            "help", "invitations", "jobs", "learn", "login", "marketplace", "messages",
            "notifications", "oauth", "places", "playoffs", "privacy", "pro", "projects",
            "resources", "search", "services", "session", "settings", "shots", "signup",
            "stories", "tags", "teams", "terms", "users"
        ]
        guard !reserved.contains(handle.lowercased()) else { return nil }
        guard handle.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return handle
    }
}
