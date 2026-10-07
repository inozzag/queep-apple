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

/// The journey paywall: a ticker of saved references, why it opened, one hook, and Pro yearly
/// (Max yearly when the wall is video or audio). The other plans stay one tap away.
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

    private var phone: some View {
        ScrollView { storyContent }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
            .overlay(alignment: .topLeading) { closeButton }
    }

    private var macCard: some View {
        ViewThatFits(in: .vertical) {
            macColumn
            ScrollView { macColumn }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 16)
        .overlay(alignment: .topLeading) { closeButton }
    }

    private var macColumn: some View {
        VStack(spacing: 0) {
            storyContent
            purchaseBar
        }
    }

    private var storyContent: some View {
        VStack(spacing: 0) {
            hero
            VStack(spacing: 18) {
                intro
                benefits
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)
        }
    }

    private var hero: some View {
        ReferenceTicker(axis: .horizontal, lanes: 2, gap: 8, bleed: 0, speed: 9)
            .frame(height: typeSize.isAccessibilitySize ? 120 : 176)
            .frame(maxWidth: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }

    private var intro: some View {
        VStack(spacing: 10) {
            if let badge = PaywallCopy.badge(reason: context.reason, resource: context.resource) {
                Text(badge)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GalleryStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(GalleryStyle.fill, in: Capsule())
                    .accessibilityLabel(badge)
                    .accessibilityIdentifier("paywall.badge")
            }
            Text(hook.title)
                .font(.title.weight(.bold))
                .foregroundStyle(GalleryStyle.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")
            Text(PaywallCopy.subtitle(for: plan))
                .font(.body)
                .foregroundStyle(GalleryStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.subtitle")
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PaywallCopy.benefits(for: plan), id: \.text) { benefit in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: benefit.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.queepThingsInk)
                        .frame(width: 22, alignment: .center)
                        .accessibilityHidden(true)
                    Text(benefit.text)
                        .font(.body)
                        .foregroundStyle(GalleryStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("paywall.benefits")
    }

    private var periodToggle: some View {
        HStack(spacing: 4) {
            periodButton("Mensal", yearly: false)
            periodButton("Anual", yearly: true)
        }
        .padding(4)
        .background(GalleryStyle.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Período da assinatura")
        .accessibilityIdentifier("paywall.period")
    }

    private func periodButton(_ title: String, yearly: Bool) -> some View {
        let selected = annual == yearly
        let discount = yearly ? discountPercent : nil
        return Button {
            annual = yearly
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? GalleryStyle.ink : GalleryStyle.secondary)
                if let discount {
                    Text("\(discount)% off")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.queepThingsInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(discount.map { "\(title), \($0)% off" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(yearly ? "paywall.annual" : "paywall.monthly")
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            periodToggle
            if hasOffer {
                Button { Task { await buy() } } label: {
                    HStack(spacing: 8) {
                        if purchasing { ProgressView().controlSize(.small).tint(Theme.queepThingsInk) }
                        Text(purchasing ? "Confirmando…" : ctaTitle)
                    }
                }
                .buttonStyle(MasterButtonStyle())
                .disabled(purchasing || (preview == nil && store.busy))
                .accessibilityLabel(ctaTitle)
                .accessibilityIdentifier("paywall.buy")
                priceBlock
            } else if loading || store.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verificando assinatura…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GalleryStyle.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    Text(store.message ?? "Nenhum plano disponível agora. Tente novamente em instantes.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GalleryStyle.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Tentar de novo") { Task { await store.load(session, refresh: true) } }
                        .buttonStyle(MasterButtonStyle())
                        .accessibilityIdentifier("paywall.retry")
                }
            }
            if let error = store.error {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.16, blue: 0.14))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.error")
            }
            Button("Ver todos os planos") {
                ProductAnalytics.paywallAllPlansTapped()
                showingPlans = true
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.homeInk)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .accessibilityIdentifier("paywall.plans")
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var priceBlock: some View {
        let line = PaywallOfferCopy.priceLine(
            price: billedPrice,
            period: annual ? .year : .month,
            trialDays: currentTrialDays,
            monthlyEquivalent: annual ? monthlyEquivalent : nil)
        return VStack(spacing: 2) {
            Text(line.primary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GalleryStyle.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let secondary = line.secondary {
                Text(secondary)
                    .font(.footnote)
                    .foregroundStyle(GalleryStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([line.primary, line.secondary].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("paywall.price")
    }

    private var footer: some View {
        HStack(spacing: 16) {
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
        .font(.footnote.weight(.medium))
        .foregroundStyle(GalleryStyle.secondary)
        .tint(GalleryStyle.secondary)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            HomeGlyph(asset: "HomeClose", size: 16, color: Theme.homeInk)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .queepGlass(.circle)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fechar")
        .accessibilityIdentifier("paywall.close")
        .padding(.leading, 12)
        .padding(.top, 12)
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
        var flag = hookFlag
        if preview == nil {
            async let loaded: Void = store.load(session)
            flag = await ProductAnalytics.paywallTitleHook() ?? flag
            await loaded
        }
        hookFlag = flag
        loading = false
        guard !reported else { return }
        reported = true
        let resolved = PaywallCopy.hook(flag: flag, reason: context.reason, resource: context.resource)
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
                            .overlay(Color.black.opacity(0.22))
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { offer = nil }
                            .accessibilityHidden(true)
                        MaxPaywall(context: context, onFinish: { offer = nil })
                            .frame(width: 520)
                            .frame(maxHeight: max(320, proxy.size.height - 64))
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
                .frame(width: 520)
                .frame(maxHeight: 680)
        }
        .frame(width: 900, height: 760)
        .environment(Session())
        #else
        MaxPaywall(context: context, preview: offer)
            .environment(Session())
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
