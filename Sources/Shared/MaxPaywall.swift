import QueepCore
import RevenueCat
import SwiftUI

/// Why a paywall is on screen. `reason` goes to analytics; `resource` is the API's name for
/// the limit that was hit, such as `media_av` or `operations`.
struct PaywallContext: Identifiable, Equatable {
    var reason: String
    var resource: String? = nil
    var id: String { reason }
}

/// During launch every paywall in the journey sells one thing: Queep Max, billed yearly.
/// One headline, what changes against the plan the person has, one price, one button.
/// The other plans stay one tap away in `SubscriptionView`.
struct MaxPaywall: View {
    let context: PaywallContext
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = SubscriptionStore.shared
    @State private var showingPlans = false

    private var package: Package? { store.journeyPackage }
    private var access: SubscriptionAccess? { store.access }
    private var paying: Bool { access?.active == true && access?.isDevelopment != true }
    private var alreadyMax: Bool { paying && access?.plan == .max }

    /// The column Max is compared with. A development session runs on Max quotas, so it
    /// compares against Free like a new account would.
    private var currentPlan: SubscriptionPlan {
        guard let access, !access.isDevelopment, access.plan != .max else { return .free }
        return access.plan
    }

    var body: some View {
        layout
            .overlay(alignment: .top) { header }
            .background(Color.white)
            .preferredColorScheme(.light)
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(32)
            #endif
            .task { await store.load(session) }
            .onAppear {
                ProductAnalytics.paywallViewed(code: context.reason, targetPlan: SubscriptionPlan.max.rawValue)
            }
            .sheet(isPresented: $showingPlans) { SubscriptionView() }
    }

    /// One column on iPhone and iPad. A Mac sheet is short and wide, so the references stand beside the offer.
    @ViewBuilder private var layout: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            ReferenceTicker(lanes: 2, gap: 10, bleed: 10)
                .frame(width: 280)
            ScrollView {
                VStack(spacing: 0) {
                    intro.padding(.top, 28)
                    PaywallComparison(current: currentPlan)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.top)
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        }
        .frame(width: 740, height: 600)
        #else
        ScrollView {
            VStack(spacing: 0) {
                hero
                intro.padding(.top, 30)
                PaywallComparison(current: currentPlan)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.top)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        #endif
    }

    /// The library's own chrome: glass chips floating over saved things.
    private var header: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                HomeGlyph(asset: "HomeClose", size: 16, color: Theme.homeInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .queepGlass(.circle)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fechar")
            .accessibilityIdentifier("paywall.close")
            Spacer(minLength: 0)
            #if os(iOS)
            Button { Task { await store.restore(session) } } label: {
                Text("Restaurar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.homePreview)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .queepGlass(.capsule)
            .disabled(store.busy)
            .accessibilityLabel("Restaurar compras")
            .accessibilityIdentifier("paywall.restore")
            #endif
        }
        .padding(.horizontal, Theme.homeNavInset)
        .padding(.top, 12)
    }

    private var hero: some View {
        ReferenceTicker(axis: .horizontal, lanes: 1, gap: 10, speed: 9)
            .frame(height: 140)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.58),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) { LogoChip(size: 60).offset(y: 16) }
    }

    private var intro: some View {
        VStack(spacing: 12) {
            if let notice = MaxPlan.notice(for: context.resource, on: currentPlan) {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(GalleryStyle.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay { Capsule().strokeBorder(GalleryStyle.ring) }
                    .accessibilityIdentifier("paywall.notice")
            }
            Text("Salve tudo com o Max")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.89)
                .foregroundStyle(GalleryStyle.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Offer

    /// Floats over the page like the library's bottom bar.
    private var purchaseBar: some View {
        VStack(spacing: 0) {
            if let package {
                offer(package)
            } else if store.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verificando assinatura…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GalleryStyle.secondary)
                }
                .padding(.vertical, 20)
            } else {
                unavailable
            }
            if let error = store.error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.16, blue: 0.14))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityIdentifier("paywall.error")
            }
            links
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .queepGlass(.card)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func offer(_ package: Package) -> some View {
        let product = package.storeProduct
        let annual = SubscriptionStore.isAnnual(package)
        let unit = annual ? "ano" : "mês"
        let trial = store.offersTrial(package)
        let launch = store.launchOffer(package)
        HStack(spacing: 8) {
            PaywallPlanLine(annual: annual, trial: trial, launch: launch)
            if let savings = launch?.percent ?? store.annualDiscount(package) {
                Text(launch == nil ? "Economize \(savings)%" : "−\(savings)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GalleryStyle.onInk)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(GalleryStyle.ink, in: Capsule())
                    .fixedSize()
            }
        }
        // The amount charged is the largest figure on the sheet; the monthly equivalent is fine print.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(launch?.price ?? product.localizedPriceString)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(GalleryStyle.ink)
                .accessibilityIdentifier("paywall.price")
            if launch != nil {
                Text(product.localizedPriceString)
                    .font(.system(size: 15, weight: .medium))
                    .strikethrough()
                    .foregroundStyle(GalleryStyle.tertiary)
                    .accessibilityLabel("Preço normal \(product.localizedPriceString)")
            }
            Text(launch.map { $0.years == 1 ? "no 1º ano" : "por ano, por \($0.years) anos" } ?? "por \(unit)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GalleryStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, 4)
        Button { Task { await buy(package) } } label: {
            HStack(spacing: 8) {
                if store.busy { ProgressView().controlSize(.small).tint(Theme.queepThingsInk) }
                Text(store.busy ? "Confirmando…" : actionTitle(trial: trial))
            }
        }
        .buttonStyle(MasterButtonStyle())
        .disabled(store.busy)
        .padding(.top, 12)
        .accessibilityIdentifier("paywall.buy")
        Text(store.message ?? finePrint(package, unit: unit, trial: trial, launch: launch))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GalleryStyle.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Text(store.message ?? "Nenhum plano disponível agora. Tente novamente em instantes.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GalleryStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Tentar de novo") { Task { await store.load(session, refresh: true) } }
                .buttonStyle(MasterButtonStyle())
                .accessibilityIdentifier("paywall.retry")
        }
        .padding(.vertical, 4)
    }

    private var links: some View {
        HStack(spacing: 16) {
            #if os(macOS)
            // The header chip would sit on the headline in a column this narrow.
            Button("Restaurar") { Task { await store.restore(session) } }
                .disabled(store.busy)
                .accessibilityLabel("Restaurar compras")
                .accessibilityIdentifier("paywall.restore")
            #endif
            if let terms = SubscriptionStore.configuredURL("QueepTermsURL") {
                Link("Termos", destination: terms)
            }
            if let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
                Link("Privacidade", destination: privacy)
            }
            Button("Todos os planos") { showingPlans = true }
                .accessibilityIdentifier("paywall.plans")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(GalleryStyle.secondary)
        .tint(GalleryStyle.secondary)
        .buttonStyle(.plain)
        .padding(.top, 10)
    }

    private func actionTitle(trial: Bool) -> String {
        if store.awaitingConfirmation { return "Atualizar assinatura" }
        if alreadyMax { return "Gerenciar assinatura" }
        if paying { return "Mudar para o Max" }
        if trial { return "Começar 7 dias grátis" }
        return "Assinar o Queep Max"
    }

    private func finePrint(_ package: Package, unit: String, trial: Bool, launch: LaunchOffer?) -> String {
        let product = package.storeProduct
        let price = product.localizedPriceString
        if trial {
            // Both plans share one subscription group, so the store grants a single free trial.
            return "Depois, \(price) por \(unit). Cancele quando quiser. "
                + "Ao começar o teste do Max, o teste do Pro deixa de estar disponível."
        }
        if let launch {
            let span = launch.years == 1 ? "no primeiro ano" : "por ano nos \(launch.years) primeiros anos"
            return "\(launch.price) \(span). Depois, \(price) por ano. Cancele quando quiser."
        }
        if SubscriptionStore.isAnnual(package), let perMonth = product.localizedPricePerMonth {
            return "Equivale a \(perMonth) por mês. Renova a cada ano; cancele quando quiser."
        }
        return "Renova a cada \(unit). Cancele quando quiser."
    }

    private func buy(_ package: Package) async {
        if store.awaitingConfirmation {
            await store.load(session, refresh: true)
            return
        }
        if alreadyMax {
            openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            return
        }
        if await store.purchase(package, session: session) { dismiss() }
    }
}

// MARK: Pieces

/// What is being bought and, during a launch price, how long it lasts.
private struct PaywallPlanLine: View {
    let annual: Bool
    let trial: Bool
    let launch: LaunchOffer?

    var body: some View {
        Group {
            if let launch, let end = launch.endsAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("\(launch.label) · \(Self.remaining(until: end, from: context.date))")
                        .monospacedDigit()
                }
            } else if let launch {
                Text("\(launch.label) · por tempo limitado")
            } else {
                Text((annual ? "Max anual" : "Max mensal") + (trial ? " · 7 dias grátis" : ""))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .tracking(-0.2)
        .foregroundStyle(GalleryStyle.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityIdentifier(launch == nil ? "paywall.plan" : "paywall.launch")
    }

    static func remaining(until end: Date, from now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "termina em \(days)d \(hours)h" }
        if hours > 0 { return "termina em \(hours)h \(minutes)min" }
        return "termina em \(max(1, minutes))min"
    }
}

/// The plan the person has beside Max, row by row, in words rather than quotas. The gallery's
/// tile holds it; Max sits on a white column so the eye lands there.
private struct PaywallComparison: View {
    let current: SubscriptionPlan
    private let currentWidth: CGFloat = 68
    private let maxWidth: CGFloat = 80
    #if os(macOS)
    private let rowInset: CGFloat = 10
    #else
    private let rowInset: CGFloat = 12
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(current.title)
                    .foregroundStyle(GalleryStyle.tertiary)
                    .frame(width: currentWidth)
                Text("Max")
                    .foregroundStyle(GalleryStyle.ink)
                    .frame(width: maxWidth)
            }
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.2)
            .frame(height: 38)
            .accessibilityHidden(true)
            ForEach(MaxPlan.rows(comparedWith: current)) { row in
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 1)
                HStack(spacing: 0) {
                    Text(row.label)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(GalleryStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cell(row.current, strong: false)
                        .frame(width: currentWidth)
                    cell(row.max, strong: true)
                        .frame(width: maxWidth)
                }
                .padding(.vertical, rowInset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label). \(current.title): \(row.current.spoken). Max: \(row.max.spoken).")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(GalleryStyle.ring)
                }
                .frame(width: maxWidth)
                .padding(6)
        }
        .background(GalleryStyle.fill)
        .galleryTile()
        .accessibilityIdentifier("paywall.comparison")
    }

    @ViewBuilder private func cell(_ value: MaxPlan.Value, strong: Bool) -> some View {
        switch value {
        case .missing:
            Text("–")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GalleryStyle.dot)
        case .included:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(strong ? GalleryStyle.ink : GalleryStyle.tertiary)
        case .limited, .less, .plenty:
            Text(value.word ?? "")
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.2)
                .lineLimit(1)
                .foregroundStyle(strong ? GalleryStyle.ink : GalleryStyle.tertiary)
        case .soon:
            // Announced, not shipped: a tag, never the check that means "you get this today".
            Text("Em breve")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GalleryStyle.secondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .overlay { Capsule().strokeBorder(GalleryStyle.ring) }
                .fixedSize()
        }
    }
}

/// What each plan gives, in the words a person would use, and the line that explains why the
/// sheet opened. No figures on purpose: quotas change on the server and this sheet should not
/// have to follow them. The exact numbers stay in Conta → Uso, which reads them from the API.
enum MaxPlan {
    enum Value: Equatable {
        case missing, included, limited, less, plenty, soon

        /// Cells that say it in a word. The others draw a mark.
        var word: String? {
            switch self {
            case .limited: "Limitado"
            case .less: "Menos"
            case .plenty: "De sobra"
            case .missing, .included, .soon: nil
            }
        }

        var spoken: String {
            switch self {
            case .missing: "não inclui"
            case .included: "inclui"
            case .limited: "limitado"
            case .less: "menos"
            case .plenty: "de sobra"
            case .soon: "em breve"
            }
        }
    }

    struct Row: Identifiable {
        let id: String
        let label: String
        let current: Value
        let max: Value
    }

    static func rows(comparedWith plan: SubscriptionPlan) -> [Row] {
        // Every plan saves and searches; what changes is how far it goes before the month resets.
        let room: Value = switch plan {
        case .free: .limited
        case .pro: .less
        case .max: .plenty
        }
        return [
            Row(id: "video", label: "Captura de Reels, TikToks e vídeos",
                current: plan == .max ? .included : .missing, max: .included),
            Row(id: "ai", label: "Capturas e buscas com IA", current: room, max: .plenty),
            Row(id: "library", label: "Espaço na biblioteca", current: room, max: .plenty),
            Row(id: "spaces", label: "Spaces para organizar",
                current: plan == .free ? .missing : .included, max: .included),
            Row(id: "mcp", label: "MCP do Queep", current: .missing, max: .soon)
        ]
    }

    /// One short line on why the sheet opened. Unknown limits show nothing rather than the API's sentence.
    static func notice(for resource: String?, on plan: SubscriptionPlan) -> String? {
        switch resource {
        case "media_av", "media_seconds": "Vídeos e áudios fazem parte do Max"
        case "operations": "Você usou as capturas deste mês"
        case "searches": "Você usou as buscas deste mês"
        case "items": "Sua biblioteca está cheia"
        case "storage_bytes": "Seu espaço acabou"
        case "upload_bytes": "Você usou o envio de arquivos deste mês"
        case "spaces": plan == .free ? "Spaces fazem parte dos planos pagos" : "Você chegou ao limite de Spaces"
        default: nil
        }
    }
}
