import Foundation

extension LinkSurface {
    /// Numeric id from behance.net/gallery/{id}/slug; never a profile or services path.
    public static func behanceProjectId(url: String?) -> String? {
        guard identify(url: url) == .behance, let path = URL(string: url ?? "")?.path else {
            return nil
        }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "gallery" else { return nil }
        let gallery = parts[1]
        guard gallery.range(of: #"^[0-9]{1,20}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return gallery
    }

    /// Designer handle from behance.net/{name}; never gallery/, search, hire, or services.
    public static func behanceProfileHandle(url: String?) -> String? {
        guard identify(url: url) == .behance, behanceProjectId(url: url) == nil,
              let path = URL(string: url ?? "")?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        let handle = parts[0]
        let reserved: Set<String> = [
            "about", "adobe", "api", "assets", "blog", "careers", "cloud", "copyright",
            "courses", "embed", "explore", "for-you", "for_you", "galleries", "gallery",
            "help", "hire", "internships", "job", "joblist", "jobs", "live", "login",
            "messages", "misc", "notifications", "oauth", "onboarding", "privacy",
            "pro", "projects", "search", "services", "settings", "signup", "talent",
            "terms", "v2", "v3"
        ]
        guard !reserved.contains(handle.lowercased()) else { return nil }
        guard handle.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return handle
    }
}
