import Foundation

/// The five titles the journey paywall can show. PostHog's `paywall_title_hook` flag
/// picks one (`a`...`e`); without a flag the reason chooses the default.
public enum PaywallHook: String, CaseIterable, Sendable {
    case a, b, c, d, e

    public var title: String {
        switch self {
        case .a: "Crie seu segundo cérebro de referências"
        case .b: "Continue construindo seu segundo cérebro"
        case .c: "Ache qualquer referência em segundos"
        case .d: "Pare de perder o que você salva"
        case .e: "Transforme horas de feed em referências pro seu trabalho"
        }
    }
}

public enum PaywallBillingPeriod: String, Sendable {
    case month, year

    public var noun: String { self == .year ? "ano" : "mês" }
}

public struct PaywallBenefit: Equatable, Sendable {
    public let symbol: String
    public let text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }
}

public struct PaywallPriceLine: Equatable, Sendable {
    public let primary: String
    public let secondary: String?

    public init(primary: String, secondary: String?) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Words on the journey paywall. Quotas stay out of here; they live on the all-plans list.
public enum PaywallCopy {
    public static let proSubtitle = "Com o Queep Pro você salva sem pensar em limite e acha tudo com uma busca, no Mac e no iPhone."
    public static let maxSubtitle = "Com o Queep Max seus vídeos e áudios viram texto que dá pra buscar."

    public static let proBenefits: [PaywallBenefit] = [
        PaywallBenefit(symbol: "photo.on.rectangle.angled", text: "Imagens e links de sobra pra salvar"),
        PaywallBenefit(symbol: "text.magnifyingglass", text: "Ache qualquer referência descrevendo o que você lembra"),
        PaywallBenefit(symbol: "rectangle.3.group", text: "Um Space pra cada projeto"),
        PaywallBenefit(symbol: "laptopcomputer.and.iphone", text: "Tudo sincronizado entre Mac e iPhone")
    ]

    public static let maxBenefits: [PaywallBenefit] = [
        PaywallBenefit(symbol: "square.stack.3d.up", text: "Tudo do Pro, com espaço de sobra"),
        PaywallBenefit(symbol: "waveform", text: "Vídeos e áudios transcritos e resumidos"),
        PaywallBenefit(symbol: "text.magnifyingglass", text: "Busque dentro do que foi dito no vídeo")
    ]

    /// The plan this opening of the paywall is selling. Media stays on Max; everything else
    /// follows the server's required plan, and a journey with no requirement sells Pro.
    public static func offeredPlan(reason: String, resource: String?, requiredPlan: SubscriptionPlan?) -> SubscriptionPlan {
        if isMedia(reason: reason, resource: resource) { return .max }
        if let requiredPlan, requiredPlan != .free { return requiredPlan }
        return .pro
    }

    public static func subtitle(for plan: SubscriptionPlan) -> String {
        plan == .max ? maxSubtitle : proSubtitle
    }

    public static func benefits(for plan: SubscriptionPlan) -> [PaywallBenefit] {
        plan == .max ? maxBenefits : proBenefits
    }

    /// Quiet reason pill. Settings and anything we don't recognize stay unlabeled.
    public static func badge(reason: String, resource: String?) -> String? {
        let reason = normalize(reason)
        let resource = resource.map(normalize)
        if isFirstSave(reason) { return "Faça seu primeiro save" }
        if isSettings(reason) || reason == "preview" || reason.isEmpty { return nil }
        if isMedia(reason: reason, resource: resource) { return "Vídeo e áudio são do Queep Max" }
        switch resource {
        case "operations", "images", "image", "captures", "capture":
            return "Seu limite de imagens acabou"
        case "items", "links", "link":
            return "Seu limite de itens acabou"
        case "searches", "search":
            return "Suas buscas do mês acabaram"
        case "storage_bytes", "storage":
            return "Seu espaço acabou"
        case "spaces":
            return "Seu limite de Spaces acabou"
        case "upload_bytes", "uploads":
            return "Seu limite de envio acabou"
        default:
            break
        }
        switch reason {
        case "storage_limit": return "Seu espaço acabou"
        case "spaces_required": return "Seu limite de Spaces acabou"
        case "plan_limit": return "Seu limite acabou"
        default: return nil
        }
    }

    /// `flag` is the raw multivariate value (`a`...`e`). Anything else uses the reason default.
    public static func hook(flag: String?, reason: String, resource: String?) -> PaywallHook {
        if let flag {
            let key = normalize(flag)
            if let variant = PaywallHook(rawValue: key) { return variant }
        }
        return defaultHook(reason: reason, resource: resource)
    }

    /// A for the first save, B when a limit opened the sheet, C for vídeo/áudio and Ajustes.
    public static func defaultHook(reason: String, resource: String?) -> PaywallHook {
        let reason = normalize(reason)
        let resource = resource.map(normalize)
        if isFirstSave(reason) { return .a }
        if isMedia(reason: reason, resource: resource) || isSettings(reason) || reason == "preview" || reason.isEmpty {
            return .c
        }
        if isLimit(reason: reason, resource: resource) { return .b }
        return .c
    }

    private static func isFirstSave(_ reason: String) -> Bool {
        reason == "first_save" || reason == "onboarding"
    }

    private static func isSettings(_ reason: String) -> Bool {
        reason == "settings" || reason == "ajustes" || reason == "account"
    }

    private static func isMedia(reason: String, resource: String?) -> Bool {
        reason == "media_av" || reason == "media_av_required" || reason == "media_seconds"
            || resource == "media_av" || resource == "media_seconds"
    }

    private static func isLimit(reason: String, resource: String?) -> Bool {
        switch reason {
        case "plan_limit", "storage_limit", "spaces_required", "upload_limit": return true
        default: break
        }
        switch resource {
        case "operations", "images", "image", "captures", "capture",
             "items", "links", "link", "searches", "search",
             "storage_bytes", "storage", "spaces", "upload_bytes", "uploads":
            return true
        default:
            return false
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum PaywallPricing {
    /// How much the yearly price saves against twelve monthly charges, rounded down.
    /// Nil when a price is missing or the year is not cheaper, so the tag can hide.
    public static func annualDiscountPercent(yearly: Decimal, monthly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        let full = monthly * 12
        guard yearly < full else { return nil }
        let saved = (full - yearly) / full * 100
        let handler = NSDecimalNumberHandler(
            roundingMode: .down, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let percent = NSDecimalNumber(decimal: saved).rounding(accordingToBehavior: handler).intValue
        return percent > 0 ? percent : nil
    }
}

public enum PaywallOfferCopy {
    /// Trial length comes from the package. No trial uses the plan name, never a fixed "7 dias".
    public static func callToAction(plan: SubscriptionPlan, trialDays: Int?) -> String {
        if let trialDays, trialDays > 0 {
            return "Começar \(trialDays) \(dayWord(trialDays)) grátis"
        }
        return "Assinar Queep \(plan.title)"
    }

    /// The billed amount is the primary line. A yearly plan can add the monthly equivalent under it.
    public static func priceLine(price: String, period: PaywallBillingPeriod, trialDays: Int?, monthlyEquivalent: String?) -> PaywallPriceLine {
        let unit = period.noun
        let primary: String
        if let trialDays, trialDays > 0 {
            primary = "Grátis por \(trialDays) \(dayWord(trialDays)), depois \(price) por \(unit)"
        } else {
            primary = "\(price) por \(unit)"
        }
        let secondary = period == .year && monthlyEquivalent.map({ !$0.isEmpty }) == true
            ? "equivale a \(monthlyEquivalent!) por mês"
            : nil
        return PaywallPriceLine(primary: primary, secondary: secondary)
    }

    private static func dayWord(_ days: Int) -> String {
        days == 1 ? "dia" : "dias"
    }
}
