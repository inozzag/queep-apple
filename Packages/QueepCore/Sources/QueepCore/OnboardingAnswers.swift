import Foundation

/// Phone, attribution and work collected before the first save.
public enum OnboardingAnswers {
    public static let sources = [
        "anuncio", "instagram", "tiktok", "twitter", "youtube", "google",
        "linkedin", "amigo", "ai_chat", "podcast", "app_store"
    ]
    public static let work = [
        "design", "marketing", "conteudo", "social", "fotografia", "publicidade",
        "produto", "empreendedor", "educacao", "outro"
    ]

    /// What they typed when work is `outro`. Nil for the listed professions.
    public static func workDetail(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (2...40).contains(trimmed.count) else { return nil }
        return trimmed
    }

    /// E.164 (`+5511988887777`) when the country code, area code and number all fit. Otherwise nil.
    public static func phone(_ raw: String) -> String? {
        let parts = PhoneNumber.parts(from: raw)
        return PhoneNumber.e164(national: parts.1, country: parts.0)
    }

    public static func link(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://" + value }
        let capture = Capture(kind: "link", title: "", text: "", url: value)
        return capture.isValid ? value : nil
    }
}
