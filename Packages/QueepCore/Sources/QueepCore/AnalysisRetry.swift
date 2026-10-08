import Foundation

/// Body for `POST v1/references/{id}/retry`. `scope` is omit-safe: servers that do not know it ignore the field.
public struct AnalysisRetryBody: Encodable, Equatable, Sendable {
    public var revision: Int
    /// `"fetch"` asks the worker to fetch the picture or clip again. `nil` leaves the key out.
    public var scope: String?

    public init(revision: Int, scope: String? = "fetch") {
        self.revision = revision
        self.scope = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(scope, forKey: .scope)
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case scope
    }
}

/// Copy shown when re-analysis is refused.
public enum AnalysisRetry {
    public static func failureCopy(_ error: Error) -> String {
        switch error {
        case QueepError.conflict:
            return "Essa referência mudou. Atualize a biblioteca e tente analisar de novo."
        case QueepError.rateLimited(let seconds):
            return limitCopy(retryAfter: seconds)
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public static func limitCopy(retryAfter seconds: Int?) -> String {
        guard let seconds else {
            return "Muitas tentativas. Espere um pouco e tente de novo."
        }
        if seconds < 1 {
            return "Muitas tentativas. Tente de novo agora."
        }
        if seconds < 60 {
            let unit = seconds == 1 ? "segundo" : "segundos"
            return "Muitas tentativas. Tente de novo em \(seconds) \(unit)."
        }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        let unit = minutes == 1 ? "minuto" : "minutos"
        return "Muitas tentativas. Tente de novo em \(minutes) \(unit)."
    }
}
