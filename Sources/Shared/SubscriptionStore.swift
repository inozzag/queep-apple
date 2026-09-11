import Foundation
import Observation
import QueepCore
import RevenueCat

/// Serializes SDK identity changes with purchases, including across Mac windows.
/// Only the authenticated API response is used to display confirmed access.
@MainActor @Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()
    private(set) var ownerID: String?
    private(set) var access: SubscriptionAccess?
    private(set) var packages: [Package] = []
    private(set) var busy = false
    private(set) var error: String?
    private(set) var message: String?
    private(set) var storeAvailable = false
    private(set) var awaitingConfirmation = false

    static func configuredURL(_ name: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: name) as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private var key: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "QueepRevenueCatKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if value.hasPrefix("test_") { return value }
        #endif
        guard value.hasPrefix("appl_"),
              Self.configuredURL("QueepPrivacyURL") != nil,
              Self.configuredURL("QueepTermsURL") != nil else { return nil }
        return value
    }

    private func prepare(_ uid: String) async throws {
        guard let key else {
            throw QueepError.server("Compras ainda não disponíveis nesta versão.")
        }
        if !Purchases.isConfigured {
            Purchases.logLevel = .error
            Purchases.configure(withAPIKey: key, appUserID: uid)
        } else if Purchases.shared.appUserID != uid {
            _ = try await Purchases.shared.logIn(uid)
        }
        guard Purchases.shared.appUserID == uid else { throw QueepError.unauthorized }
    }

    private func perform(_ session: Session,
                         operation: (String, APIClient) async throws -> Void) async {
        guard !busy, let uid = session.userID, let api = session.client() else { return }
        if ownerID != uid {
            access = nil; packages = []; storeAvailable = false; awaitingConfirmation = false
        }
        ownerID = uid
        busy = true; error = nil; message = nil
        defer {
            busy = false
            if session.userID != uid {
                access = nil; packages = []; storeAvailable = false; message = nil; error = nil
                awaitingConfirmation = false
            }
        }
        do { try await operation(uid, api) }
        catch is CancellationError { }
        catch {
            guard session.userID == uid else { return }
            let code = (error as NSError).code
            if (error as NSError).domain == ErrorCode.errorDomain {
                if code == ErrorCode.purchaseCancelledError.rawValue { return }
                if code == ErrorCode.paymentPendingError.rawValue {
                    message = "A compra aguarda aprovação. Atualize a assinatura após a confirmação."
                    return
                }
                self.error = "Não foi possível concluir. Tente novamente ou use Restaurar compras."
            } else { self.error = error.localizedDescription }
        }
    }

    func load(_ session: Session, refresh: Bool = false) async {
        await perform(session) { uid, api in
            let result = try await api.subscriptionAccess(refresh: refresh)
            guard session.userID == uid else { return }
            access = result
            if result.active { awaitingConfirmation = false }
            guard key != nil else {
                storeAvailable = false
                message = "Compras ainda não disponíveis nesta versão."
                return
            }
            try await prepare(uid)
            guard session.userID == uid else { return }
            let offerings = try await Purchases.shared.offerings()
            guard session.userID == uid else { return }
            let customer = try await Purchases.shared.customerInfo()
            guard session.userID == uid else { return }
            // A local entitlement may suppress another purchase, but never grant API access.
            awaitingConfirmation = !result.active && customer.entitlements["queep_pro"]?.isActive == true
            packages = offerings.current?.availablePackages.filter {
                $0.storeProduct.productType == .autoRenewableSubscription
            } ?? []
            storeAvailable = true
            if awaitingConfirmation {
                message = "Sua compra aguarda confirmação. Aguarde alguns segundos e atualize a assinatura."
            }
            if packages.isEmpty { message = "Nenhum plano disponível agora. Tente novamente mais tarde." }
        }
    }

    func purchase(_ package: Package, session: Session) async {
        await perform(session) { uid, api in
            try await prepare(uid)
            guard !awaitingConfirmation, session.userID == uid,
                  packages.contains(where: { $0.identifier == package.identifier })
            else { throw QueepError.unauthorized }
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled, session.userID == uid else { return }
            awaitingConfirmation = true
            let confirmed = try await api.subscriptionAccess(refresh: true)
            guard session.userID == uid else { return }
            access = confirmed
            awaitingConfirmation = !confirmed.active
            message = confirmed.isDevelopment ? "Compra de teste concluída. O acesso de desenvolvimento permanece liberado."
                : confirmed.active ? "Assinatura confirmada. Ela vale também nos seus outros dispositivos."
                : "Compra recebida. Aguarde alguns segundos e toque em Atualizar assinatura para confirmar."
        }
    }

    func restore(_ session: Session) async {
        await perform(session) { uid, api in
            try await prepare(uid)
            guard session.userID == uid else { throw QueepError.unauthorized }
            let customer = try await Purchases.shared.restorePurchases()
            guard session.userID == uid else { return }
            awaitingConfirmation = customer.entitlements["queep_pro"]?.isActive == true
            let confirmed = try await api.subscriptionAccess(refresh: true)
            guard session.userID == uid else { return }
            access = confirmed
            awaitingConfirmation = awaitingConfirmation && !confirmed.active
            message = confirmed.isDevelopment ? "Restauração solicitada na loja de teste."
                : confirmed.active ? "Sua assinatura está ativa nesta conta."
                : "Nenhuma assinatura ativa confirmada. Confira a conta da App Store e tente atualizar em instantes."
        }
    }
}
