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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
                    planSummary(.free, detail: "Sem assinatura: 12 capturas com IA, 8 buscas por mês, 100 itens e 250 MiB. Sincronize, abra e exclua suas referências no Mac e no iPhone.")
                    planSummary(.pro, detail: "100 capturas, 50 buscas por mês, até 800 itens, 2 GiB e 15 Spaces. Imagens, notas, sites e posts sociais.")
                    planSummary(.max, detail: "200 capturas, 80 buscas por mês, até 2.500 itens, 10 GiB e 40 Spaces. Inclui 40 minutos mensais de áudio e vídeo de arquivo.")
                    if store.ownerID == session.userID {
                        status
                        if let message = store.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                        if let error = store.error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red).accessibilityIdentifier("subscription.error")
                        }
                        if !store.awaitingConfirmation && (requirement == nil || requirement?.requiredPlan != nil) {
                            ForEach(visiblePackages, id: \.identifier) { package in
                                let managesInStore = SubscriptionCheckout.managesInAppStore(
                                    access: store.access, packagePlan: SubscriptionStore.plan(package))
                                Button {
                                    if managesInStore {
                                        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                                    } else {
                                        Task { await store.purchase(package, session: session) }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Queep \(SubscriptionStore.plan(package)?.title ?? "") · \(SubscriptionStore.isAnnual(package) ? "Anual" : "Mensal")").font(.headline)
                                        if managesInStore {
                                            Text("Alterar na App Store").font(.callout)
                                        }
                                        if SubscriptionStore.isAnnual(package), SubscriptionStore.plan(package) == .pro {
                                            Text("Recomendado").font(.caption.bold())
                                        }
                                        Text("\(package.storeProduct.localizedPriceString) / \(period(package))")
                                        if let discount = store.annualDiscount(package) {
                                            Text("Economize \(discount)% em relação a 12 meses do mensal").font(.caption)
                                        }
                                        if store.trialEligible.contains(package.identifier),
                                           let offerPlan = SubscriptionStore.plan(package) {
                                            Text(SubscriptionOfferCopy.trialLine(
                                                plan: offerPlan,
                                                price: package.storeProduct.localizedPriceString,
                                                period: period(package))).font(.callout)
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

    private var visiblePackages: [Package] {
        store.packages.filter { package in
            guard let plan = SubscriptionStore.plan(package) else { return false }
            if let target = requirement?.requiredPlan { return plan == target }
            return plan.rank > (store.access?.plan.rank ?? 0) || store.access?.isDevelopment == true
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

enum ConversionFocus: String, Identifiable {
    case pro, max
    var id: String { rawValue }
    var plan: SubscriptionPlan { self == .pro ? .pro : .max }
}

/// High-conversion sheet: one plan, annual selected, a single trial button.
struct ConversionPaywall: View {
    var focus: ConversionFocus
    var reason: String = "first_save"
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = SubscriptionStore.shared
    @State private var annual = true
    @State private var showingMax = false

    private var plan: SubscriptionPlan { showingMax ? .max : focus.plan }
    private var package: Package? { store.preferredPackage(plan: plan, annual: annual) }
    private var trial: Bool {
        guard let package else { return false }
        return store.offersTrial(package)
    }
    private var upgrading: Bool {
        focus == .max || showingMax
            ? (store.access?.active == true && store.access?.isDevelopment != true && store.access?.plan == .pro)
            : false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(plan == .max ? "Áudio e vídeo são do Max" : "Salve horas do seu dia")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.homeInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.title")
                    Text(plan == .max
                         ? "Transcrição e resumo do que você guarda em arquivo."
                         : "Encontrando fácil tudo que você salva.")
                        .font(.body)
                        .foregroundStyle(Theme.homePreview)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(benefits, id: \.self) { benefit in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.homeInk)
                                Text(benefit).font(.body).foregroundStyle(Theme.homeInk)
                            }
                        }
                    }
                    if let package {
                        periodRow(annual: true, package: store.package(plan: plan, annual: true))
                        periodRow(annual: false, package: store.package(plan: plan, annual: false))
                        Button { Task { await buy(package) } } label: {
                            Text(store.busy ? "Confirmando…" : actionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OnboardingPrimaryButton())
                        .disabled(store.busy)
                        .accessibilityIdentifier("paywall.buy")
                        Text(priceLine(package.storeProduct.localizedPriceString, package: package))
                            .font(.footnote)
                            .foregroundStyle(Theme.homePreview)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                        if let message = store.message {
                            Text(message).font(.callout).foregroundStyle(Theme.homePreview)
                        }
                    } else if store.busy {
                        ProgressView("Verificando assinatura…")
                    } else {
                        Text(store.message ?? "Nenhum plano disponível agora. Tente novamente em instantes.")
                            .foregroundStyle(Theme.homePreview)
                    }
                    if let error = store.error {
                        Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("paywall.error")
                    }
                    if plan == .max && trial {
                        Text("Ao começar o teste do Max, o teste do Pro deixa de estar disponível.")
                            .font(.footnote)
                            .foregroundStyle(Theme.homePreview)
                    }
                    if focus == .pro && !showingMax {
                        Button("Conhecer o Max") { showingMax = true }
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("paywall.max")
                    }
                    HStack(spacing: 16) {
                        if let privacy = SubscriptionStore.configuredURL("QueepPrivacyURL") {
                            Link("Privacidade", destination: privacy)
                        }
                        if let terms = SubscriptionStore.configuredURL("QueepTermsURL") {
                            Link("Termos", destination: terms)
                        }
                        Button("Restaurar") { Task { await store.restore(session) } }
                            .disabled(store.busy)
                            .accessibilityIdentifier("paywall.restore")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .navigationTitle(plan == .max ? "Queep Max" : "Queep Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("paywall.close")
                }
            }
        }
        .preferredColorScheme(.light)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 620)
        #endif
        .task { await store.load(session) }
        .onAppear { ProductAnalytics.paywallViewed(code: reason, targetPlan: plan.rawValue) }
        .onChange(of: showingMax) { _, max in
            guard max else { return }
            ProductAnalytics.paywallViewed(code: reason, targetPlan: "max")
        }
    }

    private var benefits: [String] {
        if plan == .max {
            return ["Áudio e vídeo transcritos e resumidos",
                    "Tudo do Pro",
                    "Mais itens, espaço e Spaces",
                    "40 minutos de mídia por mês"]
        }
        return ["Encontre pelo que você lembra",
                "Spaces para separar o que importa",
                "A mesma biblioteca no Mac e no iPhone",
                "Mais capturas e buscas por mês"]
    }

    private var actionTitle: String {
        if upgrading { return "Mudar para o Max" }
        if trial { return "Começar 7 dias grátis" }
        return "Assinar Queep \(plan.title)"
    }

    private func priceLine(_ price: String, package: Package) -> String {
        let period = SubscriptionStore.isAnnual(package) ? "ano" : "mês"
        if trial { return "7 dias grátis, depois \(price) por \(period). Cancele quando quiser." }
        return "\(price) por \(period). Cancele quando quiser."
    }

    @ViewBuilder private func periodRow(annual yearly: Bool, package: Package?) -> some View {
        if let package {
            let selected = annual == yearly || store.package(plan: plan, annual: !yearly) == nil
            Button { annual = yearly } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(yearly ? "Anual" : "Mensal").font(.headline).foregroundStyle(Theme.homeInk)
                        if store.offersTrial(package) {
                            Text("7 dias grátis").font(.caption.weight(.semibold)).foregroundStyle(Theme.homeInk)
                        }
                        if yearly, let discount = store.annualDiscount(package) {
                            Text("Economize \(discount)%").font(.caption).foregroundStyle(Theme.homePreview)
                        }
                    }
                    Spacer()
                    Text(package.storeProduct.localizedPriceString)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.homeInk)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Theme.homeInk)
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Theme.homeInk : Theme.homeLine, lineWidth: selected ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(yearly ? "paywall.annual" : "paywall.monthly")
        }
    }

    private func buy(_ package: Package) async {
        if SubscriptionCheckout.managesInAppStore(access: store.access, packagePlan: plan) {
            openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            return
        }
        await store.purchase(package, session: session)
        if store.access?.plan == plan && store.error == nil && !store.awaitingConfirmation {
            dismiss()
        }
    }
}

private struct PaywallSheet: View {
    let requirement: PlanRequirement
    @State private var reported = false

    var body: some View {
        Group {
            if requirement.resource == "media_av" {
                ConversionPaywall(focus: .max, reason: requirement.code)
            } else {
                SubscriptionView(requirement: requirement)
            }
        }
        .onAppear {
            guard !reported, requirement.resource != "media_av" else { return }
            reported = true
            ProductAnalytics.paywallViewed(requirement)
        }
    }
}

private struct SubscriptionGate: ViewModifier {
    @Environment(Session.self) private var session
    var enabled: Bool
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { enabled ? session.planRequirement : nil },
                                    set: { session.planRequirement = $0 })) { requirement in
            PaywallSheet(requirement: requirement)
        }
    }
}

extension View {
    func subscriptionGate(enabled: Bool = true) -> some View {
        modifier(SubscriptionGate(enabled: enabled))
    }
}
