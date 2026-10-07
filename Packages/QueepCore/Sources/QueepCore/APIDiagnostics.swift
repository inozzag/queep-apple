import Foundation

/// Unexpected API failures worth a crash report: HTTP 5xx and transport errors.
/// Quota, auth, and validation stay out. The path keeps the route and drops ids and query strings.
public enum APIDiagnostics: Sendable {
    public struct Failure: Sendable, Equatable {
        public var method: String
        public var path: String
        public var status: Int?
        /// `URLError` code when the session failed before an HTTP response. Nil for HTTP statuses.
        public var transportCode: Int?

        public init(method: String, path: String, status: Int?, transportCode: Int? = nil) {
            self.method = method
            self.path = path
            self.status = status
            self.transportCode = transportCode
        }
    }

    nonisolated(unsafe) public static var record: (@Sendable (Failure) -> Void)?

    public static func shouldReport(status: Int?) -> Bool {
        guard let status else { return true }
        return (500..<600).contains(status)
    }

    /// Route template. Query strings and UUID segments never leave the device.
    public static func route(_ path: String) -> String {
        let withoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? path
        return withoutQuery.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            let value = String(segment)
            if value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
                              options: .regularExpression) != nil {
                return ":id"
            }
            return value
        }.joined(separator: "/")
    }

    public static func report(method: String, path: String, status: Int?, transportCode: Int? = nil) {
        guard shouldReport(status: status) else { return }
        record?(Failure(method: method, path: route(path), status: status, transportCode: transportCode))
    }
}

/// Drops note text, saved URLs, search queries, file names, tokens, emails, and passwords
/// before an event leaves the device.
public enum DiagnosticScrubber {
    public static func dropsKey(_ key: String) -> Bool {
        let folded = key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        if folded == "file" || folded.hasSuffix("filename") || folded.hasSuffix("filepath") { return true }
        let blocked = [
            "url", "uri", "query", "search", "body", "note", "filename", "token", "password",
            "passwd", "email", "secret", "authorization", "cookie", "dsn", "phrase"
        ]
        return blocked.contains { folded.contains($0.replacingOccurrences(of: "_", with: "")) }
    }

    public static func redact(_ text: String) -> String {
        var result = replacing(text, pattern: #"https?://\S+"#)
        result = replacing(result, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
        return result
    }

    public static func scrub(_ payload: [String: Any]) -> [String: Any] {
        var clean: [String: Any] = [:]
        for (key, value) in payload where !dropsKey(key) {
            clean[key] = scrubbed(value)
        }
        return clean
    }

    private static func scrubbed(_ value: Any) -> Any {
        if let text = value as? String { return redact(text) }
        if let nested = value as? [String: Any] { return scrub(nested) }
        if let list = value as? [Any] { return list.map(scrubbed) }
        return value
    }

    private static func replacing(_ text: String, pattern: String,
                                  options: NSRegularExpression.Options = []) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "[redacted]")
    }
}
