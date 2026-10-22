import SwiftUI
import RevenueCat
import QueepCore

struct SubscriptionView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @Environment(LibraryStore.self) private var library
    @State private var store = SubscriptionStore.shared
    /// Pushed inside Ajustes. Back returns to that list; Fechar still dismisses the sheet.
    var pushedInSettings = false
    var requirement: PlanRequirement? = nil
    /// Ajustes shows the current plan and Apple's management. Selling stays on the journey paywall.
    var managesOnly = false

    var body: some View {
        Group {
            if pushedInSettings {
                detail
            } else {
                NavigationStack { detail }
                    #if os(macOS)
                    .frame(minWidth: 460, idealWidth: 520, minHeight: 540)
                    #endif
            }
        }
        .task(id: session.userID) { await store.load(session) }
        .onChange(of: phase) { _, newValue in
            if newValue == .active { Task { await store.load(session) } }
        }
    }

    private var detail: some View {
        SettingsPage(title: managesOnly ? "Sua assinatura" : "Assinatura",
                     subtitle: managesOnly
                        ? "O plano vale no Mac e no iPhone. Cobrança e cancelamento ficam com a Apple."
                        : "Salve imagens, links e notas. Encontre pelo que você lembra, no Mac e no iPhone.",
                     closeIdentifier: "subscription.close",
                     close: close) {
            if let requirement {
                VStack(alignment: .leading, spacing: 6) {
                    Text(requirement.message)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if requirement.requiredPlan == nil, let reset = requirement.resetsAt {
                        Text("Sua cota mensal renova em \(reset.formatted(date: .abbreviated, time: .shortened)). Você pode continuar abrindo e excluindo suas referências.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.fill, radius: Theme.radius)
            }
            if store.ownerID == session.userID { status }
            if !managesOnly {
                SettingsSection(title: "Planos") {
                    VStack(spacing: 6) {
                        planSummary(.free, icon: "ri-bookmark-line",
                                    detail: "Sem assinatura: 12 capturas com IA, 8 buscas por mês, 100 itens e 250 MiB. Sincronize, abra e exclua suas referências no Mac e no iPhone.")
                        planSummary(.pro, icon: "ri-gallery-line",
                                    detail: "100 capturas, 50 buscas por mês, até 800 itens, 2 GiB e 15 Spaces. Imagens, notas, sites e posts sociais.")
                        planSummary(.max, icon: "ri-vip-crown-line",
                                    detail: "200 capturas, 80 buscas por mês, até 2.500 itens, 10 GiB e 40 Spaces. Inclui 40 minutos mensais de áudio e vídeo de arquivo.")
                    }
                }
            }
            if store.ownerID == session.userID {
                if let message = store.message {
                    SettingsNotice(text: message)
                }
                if let error = store.error {
                    SettingsNotice(text: error, failure: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(error)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("subscription.error")
                }
                if !managesOnly && !store.awaitingConfirmation && (requirement == nil || requirement?.requiredPlan != nil),
                   !visiblePackages.isEmpty {
                    SettingsSection(title: "Assinar") {
                        VStack(spacing: 6) {
                            ForEach(visiblePackages, id: \.identifier) { package in
                                packageRow(package)
                            }
                        }
                    }
                }
            }
            if store.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verificando assinatura…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Restaurar compras") { Task { await store.restore(session) } }
                        .buttonStyle(.queep(.neutral))
                        .disabled(store.busy || !store.storeAvailable)
                        .accessibilityIdentifier("subscription.restore")
                    Button("Atualizar assinatura") { Task { await store.load(session, refresh: true) } }
                        .buttonStyle(.queep(.neutral))
                        .disabled(store.busy)
                        .accessibilityIdentifier("subscription.refresh")
                }
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack(spacing: 8) {
                        QueepIcon("ri-apple-fill", size: 18, color: Theme.ink)
                        Text("Gerenciar na App Store")
                    }
                }
                .buttonStyle(.queep(.outline))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Assinaturas renovam automaticamente. Você pode cancelar pela App Store; o acesso segue até o vencimento. Suas referências salvas continuam disponíveis para consulta e exclusão.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
                        Link("Privacidade", destination: privacy)
                    }
                    if let terms = SubscriptionStore.configuredURL("QueepTermsURL") {
                        Link("Termos de uso", destination: terms)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .tint(Theme.ink)
            }
            .padding(.horizontal, 4)
        }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }

    @ViewBuilder private var status: some View {
        if let access = store.access {
            HStack(spacing: 14) {
                IconTile(asset: access.active ? "ri-vip-crown-line" : "ri-user-line",
                         fill: access.active ? Theme.lime.opacity(0.5) : Theme.fill,
                         color: access.active ? Theme.forest : Theme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(access.isDevelopment ? "Acesso de desenvolvimento" : "Queep \(access.plan.title)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("subscription.status")
                        PlanBadge(plan: access.plan)
                    }
                    if access.isDevelopment {
                        Text("A cobrança está desativada neste ambiente.")
                            .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    } else if let date = access.expiresAt {
                        Text("\(access.willRenew ? "Renovação" : "Vencimento"): \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.chromeInset + 6)
            .surface(.outline, radius: Theme.radius)
        }
    }

    private func packageRow(_ package: Package) -> some View {
        let plan = SubscriptionStore.plan(package)
        let annual = SubscriptionStore.isAnnual(package)
        let managesInStore = SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: plan)
        return Button {
            if managesInStore {
                openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            } else {
                Task { await store.purchase(package, session: session) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconTile(asset: plan == .max ? "ri-vip-crown-line" : "ri-gallery-line",
                         fill: annual ? Theme.lime.opacity(0.5) : Theme.fill,
                         color: annual ? Theme.forest : Theme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Queep \(plan?.title ?? "") · \(annual ? "Anual" : "Mensal")")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        if annual, plan == .max { OfferTag(text: "Recomendado") }
                    }
                    Text("\(package.storeProduct.localizedPriceString) / \(period(package))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                    if let discount = store.annualDiscount(package) {
                        Text("Economize \(discount)% em relação a 12 meses do mensal")
                            .font(.system(size: 12)).foregroundStyle(Theme.forest)
                    }
                    if let days = store.trialDays(for: package), plan != nil {
                        Text(PaywallOfferCopy.priceLine(
                            price: package.storeProduct.localizedPriceString,
                            period: annual ? .year : .month, trialDays: days, monthlyEquivalent: nil).primary)
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    if managesInStore {
                        Text("Alterar na App Store").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 8)
                QueepIcon(managesInStore ? "ri-arrow-right-up-line" : "ri-arrow-right-s-line", size: 20, color: Theme.inkFaint)
                    .padding(.top, 12)
                    .padding(.trailing, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .disabled(store.busy)
        .accessibilityIdentifier("subscription.buy.\(package.identifier)")
    }

    /// Max first, yearly before monthly: the launch offer leads the list.
    private var visiblePackages: [Package] {
        store.packages.filter { package in
            guard let plan = SubscriptionStore.plan(package) else { return false }
            if let target = requirement?.requiredPlan { return plan == target }
            return plan.rank > (store.access?.plan.rank ?? 0) || store.access?.isDevelopment == true
        }
        .sorted { lhs, rhs in
            let l = SubscriptionStore.plan(lhs)?.rank ?? 0, r = SubscriptionStore.plan(rhs)?.rank ?? 0
            return l == r ? SubscriptionStore.isAnnual(lhs) && !SubscriptionStore.isAnnual(rhs) : l > r
        }
    }

    private func planSummary(_ plan: SubscriptionPlan, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(asset: icon)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Queep \(plan.title)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if store.access?.plan == plan { OfferTag(text: "Seu plano") }
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
    }

    private func period(_ package: Package) -> String {
        guard let duration = package.storeProduct.subscriptionPeriod else { return "período" }
        let unit: String
        switch duration.unit {
        case .day: unit = duration.value == 1 ? "dia" : "dias"
        case .week: unit = duration.value == 1 ? "semana" : "semanas"
        case .month: unit = duration.value == 1 ? "mês" : "meses"
        case .year: unit = duration.value == 1 ? "ano" : "anos"
        @unknown default: unit = "período"
        }
        return duration.value == 1 ? unit : "\(duration.value) \(unit)"
    }
}

/// A limit with nothing left to buy (already on the top plan) explains when the quota renews.
/// Anything that names a higher plan opens the journey paywall.
private struct SubscriptionGate: ViewModifier {
    @Environment(Session.self) private var session
    var enabled: Bool

    private var renewal: Binding<PlanRequirement?> {
        Binding(
            get: {
                guard enabled, let requirement = session.planRequirement, requirement.requiredPlan == nil else { return nil }
                return requirement
            },
            set: { if $0 == nil { session.planRequirement = nil } })
    }

    private var offer: Binding<PaywallContext?> {
        Binding(
            get: {
                guard enabled, let requirement = session.planRequirement, requirement.requiredPlan != nil else { return nil }
                return PaywallContext(reason: requirement.code, resource: requirement.resource,
                                      requiredPlan: requirement.requiredPlan)
            },
            set: { if $0 == nil { session.planRequirement = nil } })
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: renewal) { requirement in
                RenewalNotice(requirement: requirement)
            }
            .journeyPaywall(offer)
    }
}

private struct RenewalNotice: View {
    let requirement: PlanRequirement
    @State private var reported = false

    var body: some View {
        SubscriptionView(requirement: requirement)
            .onAppear {
                guard !reported else { return }
                reported = true
                ProductAnalytics.paywallViewed(requirement)
            }
    }
}

extension View {
    func subscriptionGate(enabled: Bool = true) -> some View {
        modifier(SubscriptionGate(enabled: enabled))
    }
}
