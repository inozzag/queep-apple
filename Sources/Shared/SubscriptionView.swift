import SwiftUI
import RevenueCat
import QueepCore

struct SubscriptionView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var store = SubscriptionStore.shared
    var requirement: PlanRequirement? = nil
    /// Ajustes shows the current plan and Apple's management. Selling stays on the journey paywall.
    var managesOnly = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if managesOnly {
                        Text("Sua assinatura")
                            .font(.title2.bold())
                        Text("O plano vale no Mac e no iPhone. Cobrança e cancelamento ficam com a Apple.")
                            .foregroundStyle(.secondary)
                    } else {
                    Label("Suas referências, sempre à mão", systemImage: "bookmark.square")
                        .font(.title2.bold())
                    Text("Salve imagens, links e notas. Encontre pelo que você lembra, no Mac e no iPhone.")
                        .foregroundStyle(.secondary)
                    if let requirement {
                        Text(requirement.message).font(.headline)
                        if requirement.requiredPlan == nil, let reset = requirement.resetsAt {
                            Text("Sua cota mensal renova em \(reset.formatted(date: .abbreviated, time: .shortened)). Você pode continuar abrindo e excluindo suas referências.")
                        }
                    }
                    if !managesOnly {
                    planSummary(.free, detail: "Sem assinatura: 12 capturas com IA, 8 buscas por mês, 100 itens e 250 MiB. Sincronize, abra e exclua suas referências no Mac e no iPhone.")
                    planSummary(.pro, detail: "100 capturas, 50 buscas por mês, até 800 itens, 2 GiB e 15 Spaces. Imagens, notas, sites e posts sociais.")
                    planSummary(.max, detail: "200 capturas, 80 buscas por mês, até 2.500 itens, 10 GiB e 40 Spaces. Inclui 40 minutos mensais de áudio e vídeo de arquivo.")
                    }
                    }
                    if store.ownerID == session.userID {
                        status
                        if let message = store.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                        if let error = store.error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red).accessibilityIdentifier("subscription.error")
                        }
                        if !managesOnly && !store.awaitingConfirmation && (requirement == nil || requirement?.requiredPlan != nil) {
                            ForEach(visiblePackages, id: \.identifier) { package in
                                Button {
                                    let target = SubscriptionStore.plan(package)
                                    if SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: target) {
                                        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                                    } else {
                                        Task { await store.purchase(package, session: session) }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Queep \(SubscriptionStore.plan(package)?.title ?? "") · \(SubscriptionStore.isAnnual(package) ? "Anual" : "Mensal")").font(.headline)
                                        if SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: SubscriptionStore.plan(package)) {
                                            Text("Alterar na App Store").font(.callout)
                                        }
                                        if SubscriptionStore.isAnnual(package), SubscriptionStore.plan(package) == .max {
                                            Text("Recomendado").font(.caption.bold())
                                        }
                                        Text("\(package.storeProduct.localizedPriceString) / \(period(package))")
                                        if let discount = store.annualDiscount(package) {
                                            Text("Economize \(discount)% em relação a 12 meses do mensal").font(.caption)
                                        }
                                        if let days = store.trialDays(for: package), let plan = SubscriptionStore.plan(package) {
                                            let period: PaywallBillingPeriod = SubscriptionStore.isAnnual(package) ? .year : .month
                                            Text(PaywallOfferCopy.priceLine(
                                                price: package.storeProduct.localizedPriceString,
                                                period: period, trialDays: days, monthlyEquivalent: nil).primary)
                                                .font(.callout)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                }.buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("subscription.buy.\(package.identifier)")
                                    .disabled(store.busy)
                            }
                        }
                    }
                    if store.busy { ProgressView("Verificando assinatura…") }
                    Button("Restaurar compras") { Task { await store.restore(session) } }
                        .disabled(store.busy || !store.storeAvailable)
                        .accessibilityIdentifier("subscription.restore")
                    Button("Atualizar assinatura") { Task { await store.load(session, refresh: true) } }
                        .disabled(store.busy).accessibilityIdentifier("subscription.refresh")
                    Link("Gerenciar na App Store", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    Text("Assinaturas renovam automaticamente. Você pode cancelar pela App Store; o acesso segue até o vencimento. Suas referências salvas continuam disponíveis para consulta e exclusão.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
                        Link("Privacidade", destination: privacy)
                    }
                    if let terms = SubscriptionStore.configuredURL("QueepTermsURL") {
                        Link("Termos de uso", destination: terms)
                    }
                }.padding(24).frame(maxWidth: 540, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Assinatura")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.accessibilityIdentifier("subscription.close")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 540)
        #endif
        .task(id: session.userID) { await store.load(session) }
        .onChange(of: phase) { _, newValue in
            if newValue == .active { Task { await store.load(session) } }
        }
    }

    @ViewBuilder private var status: some View {
        if let access = store.access {
            VStack(alignment: .leading, spacing: 6) {
                Label(access.isDevelopment ? "Acesso de desenvolvimento" : "Queep \(access.plan.title)",
                      systemImage: access.active ? "checkmark.seal" : "person.crop.circle")
                    .font(.headline).accessibilityIdentifier("subscription.status")
                if access.isDevelopment {
                    Text("A cobrança está desativada neste ambiente.").font(.callout)
                } else if let date = access.expiresAt {
                    Text("\(access.willRenew ? "Renovação" : "Vencimento"): \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.callout)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
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

    private func planSummary(_ plan: SubscriptionPlan, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Queep \(plan.title)").font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
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
