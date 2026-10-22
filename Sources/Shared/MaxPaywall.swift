import QueepCore
import RevenueCat
import SwiftUI

/// Why a paywall is on screen. `reason` goes to analytics; `resource` is the API's name for
/// the limit that was hit, such as `media_av` or `operations`.
struct PaywallContext: Identifiable, Equatable {
    var reason: String
    var resource: String? = nil
    /// The plan the server says would clear this wall. Nil on the first-save journey, which sells Pro.
    var requiredPlan: SubscriptionPlan? = nil
    var id: String { "\(reason)|\(resource ?? "")|\(requiredPlan?.rawValue ?? "")" }
}

/// Prices and trial length for previews, so the sheet can be reviewed without StoreKit.
struct PaywallPreviewOffer {
    var yearlyPrice: String
    var monthlyPrice: String
    var yearlyPerMonth: String
    var discountPercent: Int?
    var yearlyTrialDays: Int?
    var monthlyTrialDays: Int?

    static let proTrial = PaywallPreviewOffer(
        yearlyPrice: "R$ 249,90", monthlyPrice: "R$ 29,90", yearlyPerMonth: "R$ 20,83",
        discountPercent: 30, yearlyTrialDays: 7, monthlyTrialDays: nil)
    static let proPlain = PaywallPreviewOffer(
        yearlyPrice: "R$ 249,90", monthlyPrice: "R$ 29,90", yearlyPerMonth: "R$ 20,83",
        discountPercent: 30, yearlyTrialDays: nil, monthlyTrialDays: nil)
    static let maxTrial = PaywallPreviewOffer(
        yearlyPrice: "R$ 999,90", monthlyPrice: "R$ 129,90", yearlyPerMonth: "R$ 83,33",
        discountPercent: 35, yearlyTrialDays: 7, monthlyTrialDays: nil)
}

/// The journey paywall from the Figma template: the cloud art with why it opened and one hook,
/// then Queep and the plan, Mensal or Anual, the price, the benefits and one action. Pro yearly by
/// default, Max when the wall is video or audio. The other plans stay one tap away.
struct MaxPaywall: View {
    let context: PaywallContext
    var preview: PaywallPreviewOffer? = nil
    var onFinish: (() -> Void)? = nil

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var store = SubscriptionStore.shared
    @State private var annual = true
    @State private var hookFlag: String?
    @State private var showingPlans = false
    @State private var reported = false
    @State private var completed = false
    @State private var loading = true

    private var plan: SubscriptionPlan {
        PaywallCopy.offeredPlan(reason: context.reason, resource: context.resource, requiredPlan: context.requiredPlan)
    }
    private var hook: PaywallHook {
        PaywallCopy.hook(flag: hookFlag, reason: context.reason, resource: context.resource)
    }
    private var package: Package? {
        guard preview == nil else { return nil }
        return store.packageForJourney(plan: plan, annual: annual)
    }

    var body: some View {
        Group {
            #if os(macOS)
            macCard
            #else
            phone
            #endif
        }
        .preferredColorScheme(.light)
        .task { await prepare() }
        .onChange(of: annual) { _, isAnnual in
            ProductAnalytics.paywallPeriodToggled(period: isAnnual ? "year" : "month")
        }
        .onDisappear {
            guard !completed else { return }
            ProductAnalytics.paywallClosed(reason: context.reason)
        }
        .sheet(isPresented: $showingPlans) { SubscriptionView() }
    }

    // MARK: Layout

    /// iPhone: the art as a hero with the hook over it, the plan below, the action pinned.
    private var phone: some View {
        ScrollView {
            VStack(spacing: 0) {
                art
                    .frame(height: typeSize.isAccessibilitySize ? 220 : 300)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .padding(.horizontal, 8)
                planColumn
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                purchaseButton
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Theme.surface)
        }
    }

    /// Mac: the Figma card, 786pt wide: art on the left, the plan column on the right.
    private var macCard: some View {
        // The plan column sets the height; the art fills whatever that is.
        HStack(spacing: 0) {
            Color.clear.frame(width: 364)
            ViewThatFits(in: .vertical) {
                macColumn
                ScrollView { macColumn }
                    .scrollIndicators(.hidden)
            }
            .frame(width: 422)
            .frame(minHeight: 559)
            .background(Theme.surface)
        }
        .background(alignment: .leading) { art.frame(width: 364) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 42, x: -8, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
    }

    private var macColumn: some View {
        VStack(spacing: 17) {
            planColumn
            purchaseButton
            footer
        }
        .frame(width: 267)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    /// The clouds, the reason and the hook. The close button sits on the art.
    private var art: some View {
        PromoStage(style: .paywall)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    if let badge = PaywallCopy.badge(reason: context.reason, resource: context.resource) {
                        Text(badge)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(.white.opacity(0.16), in: Capsule())
                            .accessibilityLabel(badge)
                            .accessibilityIdentifier("paywall.badge")
                    }
                    Text(hook.title)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("paywall.title")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(colors: [Theme.nightDeep.opacity(0), Theme.nightDeep.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topLeading) { closeButton }
    }

    /// Lockup and plan, period, price, benefits: the right side of the Figma card.
    private var planColumn: some View {
        VStack(spacing: 17) {
            HStack(spacing: 9) {
                QueepMark(size: 36.5)
                Text("Queep")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.75)
                    .foregroundStyle(Theme.ink)
                PlanBadge(plan: plan, size: .large)
            }
            .frame(height: 60)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Queep \(plan.title)")
            periodToggle
            priceBox
            benefits
            if let error = store.error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.error")
            }
        }
    }

    private var periodToggle: some View {
        QueepSegment(
            items: [
                .init(title: "Mensal", value: false, identifier: "paywall.monthly"),
                .init(title: "Anual", value: true, tag: discountPercent.map { "\($0)% off" }, identifier: "paywall.annual"),
            ],
            selection: $annual,
            accent: .lime,
            stretches: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Período da assinatura")
            .accessibilityIdentifier("paywall.period")
    }

    /// The billed amount leads; the trial or the monthly equivalent sits under it.
    @ViewBuilder private var priceBox: some View {
        Group {
            if hasOffer {
                let line = PaywallOfferCopy.priceLine(
                    price: billedPrice,
                    period: annual ? .year : .month,
                    trialDays: currentTrialDays,
                    monthlyEquivalent: annual ? monthlyEquivalent : nil)
                VStack(spacing: 4) {
                    Text("\(Text(billedPrice).font(.system(size: 26, weight: .bold)))\(Text(annual ? "/ano" : "/mês").font(.system(size: 16)))")
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let caption = priceCaption(line) {
                        Text(caption)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([line.primary, line.secondary].compactMap { $0 }.joined(separator: ", "))
                .accessibilityIdentifier("paywall.price")
            } else if loading || store.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verificando assinatura…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            } else {
                VStack(spacing: 10) {
                    Text(store.message ?? "Nenhum plano disponível agora. Tente novamente em instantes.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Tentar de novo") { Task { await store.load(session, refresh: true) } }
                        .buttonStyle(.queep(.neutral, height: 36, stretches: false))
                        .accessibilityIdentifier("paywall.retry")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.chrome)
        .surface(.outline, radius: Theme.radius)
    }

    /// Under the price: the trial, or what a year costs per month. Never repeats the price itself.
    private func priceCaption(_ line: PaywallPriceLine) -> String? {
        if let trial = currentTrialDays, trial > 0 {
            return "Grátis por \(trial) \(trial == 1 ? "dia" : "dias"), depois cobrado por \(annual ? "ano" : "mês")"
        }
        return line.secondary
    }

    private var benefits: some View {
        VStack(spacing: 6) {
            ForEach(PaywallCopy.benefits(for: plan), id: \.text) { benefit in
                HStack(spacing: 12) {
                    IconTile(asset: Self.icon(for: benefit.symbol))
                    Text(benefit.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.chromeInset)
        .surface(.outline, radius: Theme.radius)
        .accessibilityIdentifier("paywall.benefits")
    }

    /// Remix icons for the benefits, which QueepCore names with SF Symbols.
    private static func icon(for symbol: String) -> String {
        switch symbol {
        case "photo.on.rectangle.angled": "ri-gallery-line"
        case "text.magnifyingglass": "ri-search-eye-line"
        case "rectangle.3.group": "ri-folder-6-line"
        case "laptopcomputer.and.iphone": "ri-device-line"
        case "square.stack.3d.up": "ri-stack-line"
        case "waveform": "ri-voiceprint-line"
        default: "ri-sparkling-2-line"
        }
    }

    @ViewBuilder private var purchaseButton: some View {
        if hasOffer {
            Button { Task { await buy() } } label: {
                HStack(spacing: 8) {
                    if purchasing { ProgressView().controlSize(.small).tint(Theme.onLime) }
                    Text(purchasing ? "Confirmando…" : ctaTitle)
                }
            }
            .buttonStyle(.queep(.promo, height: 48))
            .disabled(purchasing || (preview == nil && store.busy))
            .accessibilityLabel(ctaTitle)
            .accessibilityIdentifier("paywall.buy")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Ver todos os planos") {
                ProductAnalytics.paywallAllPlansTapped()
                showingPlans = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier("paywall.plans")
            HStack(spacing: 14) {
                Button("Restaurar compras") { Task { await store.restore(session) } }
                    .disabled(preview != nil || store.busy)
                    .accessibilityIdentifier("paywall.restore")
                if let terms = SubscriptionStore.configuredURL("QueepTermsURL") {
                    Link("Termos", destination: terms)
                }
                if let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
                    Link("Privacidade", destination: privacy)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.inkFaint)
            .tint(Theme.inkFaint)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            QueepIcon("ri-close-large-line", size: 24, color: .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fechar")
        .accessibilityIdentifier("paywall.close")
        .padding(.leading, 10)
        .padding(.top, 10)
    }

    private var hasOffer: Bool { preview != nil || package != nil }
    private var purchasing: Bool { preview == nil && store.busy && package != nil }

    private var currentTrialDays: Int? {
        if let preview {
            return annual ? preview.yearlyTrialDays : preview.monthlyTrialDays
        }
        guard let package else { return nil }
        return store.trialDays(for: package)
    }

    private var billedPrice: String {
        if let preview { return annual ? preview.yearlyPrice : preview.monthlyPrice }
        guard let package else { return "" }
        if currentTrialDays == nil, let launch = store.launchOffer(package) { return launch.price }
        return package.storeProduct.localizedPriceString
    }

    private var monthlyEquivalent: String? {
        if let preview { return annual ? preview.yearlyPerMonth : nil }
        guard let package else { return nil }
        if currentTrialDays == nil, let launch = store.launchOffer(package) { return launch.perMonth }
        return store.monthlyEquivalent(package)
    }

    private var discountPercent: Int? {
        if let preview { return preview.discountPercent }
        guard let yearly = store.packageForJourney(plan: plan, annual: true),
              let monthly = store.packageForJourney(plan: plan, annual: false) else { return nil }
        return PaywallPricing.annualDiscountPercent(
            yearly: yearly.storeProduct.price, monthly: monthly.storeProduct.price)
    }

    private var ctaTitle: String {
        if preview == nil && store.awaitingConfirmation { return "Atualizar assinatura" }
        if preview == nil && SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: plan) {
            return "Gerenciar na App Store"
        }
        return PaywallOfferCopy.callToAction(plan: plan, trialDays: currentTrialDays)
    }

    private func prepare() async {
        guard !reported else { return }
        if preview == nil {
            async let loaded: Void = store.load(session)
            let cached = ProductAnalytics.paywallTitleHook { fresh in
                hookFlag = fresh
            }
            if hookFlag == nil { hookFlag = cached }
            await loaded
        }
        loading = false
        guard !reported else { return }
        reported = true
        let resolved = PaywallCopy.hook(flag: hookFlag, reason: context.reason, resource: context.resource)
        ProductAnalytics.paywallViewed(
            reason: context.reason,
            hook: resolved.rawValue,
            plan: plan.rawValue,
            period: annual ? "year" : "month",
            trialEligible: currentTrialDays != nil)
    }

    private func buy() async {
        let period = annual ? "year" : "month"
        let trial = currentTrialDays != nil
        ProductAnalytics.paywallCTATapped(plan: plan.rawValue, period: period, trial: trial)
        guard preview == nil else { return }
        if store.awaitingConfirmation {
            await store.load(session, refresh: true)
            return
        }
        let selling = package.flatMap(SubscriptionStore.plan) ?? plan
        if SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: selling) {
            openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            return
        }
        guard let package else { return }
        if await store.purchase(package, session: session) {
            completed = true
            if trial {
                ProductAnalytics.paywallTrialStarted(plan: plan.rawValue, period: period)
            } else {
                ProductAnalytics.paywallPurchaseCompleted(plan: plan.rawValue, period: period)
            }
            close()
        }
    }

    private func close() {
        if let onFinish { onFinish() } else { dismiss() }
    }
}

extension View {
    /// iPhone covers the screen. Mac floats a 520pt card over the dimmed app.
    func journeyPaywall(_ offer: Binding<PaywallContext?>) -> some View {
        modifier(JourneyPaywallModifier(offer: offer))
    }
}

private struct JourneyPaywallModifier: ViewModifier {
    @Binding var offer: PaywallContext?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay {
            if let context = offer {
                GeometryReader { proxy in
                        ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.white.opacity(0.35))
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { offer = nil }
                            .accessibilityHidden(true)
                        MaxPaywall(context: context, onFinish: { offer = nil })
                            .frame(width: 786)
                            .frame(maxHeight: max(420, proxy.size.height - 64))
                    }
                }
            }
        }
        #else
        content.fullScreenCover(item: $offer) { context in
            MaxPaywall(context: context)
        }
        #endif
    }
}

#if DEBUG
private struct PaywallPreviewCanvas: View {
    let context: PaywallContext
    let offer: PaywallPreviewOffer

    var body: some View {
        #if os(macOS)
        ZStack {
            Color.black.opacity(0.18)
            MaxPaywall(context: context, preview: offer)
                .frame(width: 786)
                .frame(maxHeight: 700)
        }
        .frame(width: 1000, height: 780)
        .environment(Session())
        .environment(LibraryStore())
        #else
        MaxPaywall(context: context, preview: offer)
            .environment(Session())
            .environment(LibraryStore())
        #endif
    }
}

#Preview("Primeiro save, com teste") {
    PaywallPreviewCanvas(context: PaywallContext(reason: "first_save"), offer: .proTrial)
}

#Preview("Limite de Spaces") {
    PaywallPreviewCanvas(
        context: PaywallContext(reason: "plan_limit", resource: "spaces", requiredPlan: .pro),
        offer: .proPlain)
}

#Preview("Vídeo e áudio") {
    PaywallPreviewCanvas(
        context: PaywallContext(reason: "media_av_required", resource: "media_av", requiredPlan: .max),
        offer: .maxTrial)
}

#Preview("Sem teste") {
    PaywallPreviewCanvas(context: PaywallContext(reason: "first_save"), offer: .proPlain)
}
#endif
