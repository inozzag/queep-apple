import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var store = SubscriptionStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Suas referências, sempre à mão", systemImage: "bookmark.square")
                        .font(.title2.bold())
                    Text("Salve imagens, links e notas. Encontre pelo que você lembra, no Mac e no iPhone.")
                        .foregroundStyle(.secondary)
                    if store.ownerID == session.userID {
                        status
                        if let message = store.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                        if let error = store.error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red).accessibilityIdentifier("subscription.error")
                        }
                        if !store.awaitingConfirmation && (store.access?.active != true || store.access?.isDevelopment == true) {
                            ForEach(store.packages, id: \.identifier) { package in
                                Button {
                                    Task { await store.purchase(package, session: session) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(package.storeProduct.localizedTitle).font(.headline)
                                        Text("\(package.storeProduct.localizedPriceString) / \(period(package))")
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
                Label(access.isDevelopment ? "Acesso de desenvolvimento" : access.active ? "Assinatura ativa" : "Sem assinatura ativa",
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
