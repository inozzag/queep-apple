import Foundation

/// Phone, attribution and work collected before the first save.
public enum OnboardingAnswers {
    public static let sources = ["anuncio", "twitter", "instagram", "amigo", "ai_chat"]
    public static let work = ["marketing", "design", "produto", "conteudo", "educacao", "outro"]

    /// Digits only, with a leading + when the person typed one. Nil when the length is unusable.
    public static func phone(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard (8...15).contains(digits.count) else { return nil }
        return trimmed.hasPrefix("+") ? "+" + digits : digits
    }

    public static func link(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://" + value }
        let capture = Capture(kind: "link", title: "", text: "", url: value)
        return capture.isValid ? value : nil
    }
}
