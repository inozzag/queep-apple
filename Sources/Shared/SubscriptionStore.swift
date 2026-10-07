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
    private(set) var trialEligible: Set<String> = []
    private var pendingPlan: SubscriptionPlan?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var message: String?
    private(set) var storeAvailable = false
    private(set) var awaitingConfirmation = false

    func clearSession(_ session: Session) async {
        while busy && session.userID == nil {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard session.userID == nil, !busy else { return }
        busy = true
        defer { busy = false }
        ownerID = nil; access = nil; packages = []; error = nil; message = nil
        storeAvailable = false; awaitingConfirmation = false
        pendingPlan = nil; trialEligible = []
        if Purchases.isConfigured && !Purchases.shared.isAnonymous {
            _ = try? await Purchases.shared.logOut()
        }
    }

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
            Purchases.configure(with: Configuration.Builder(withAPIKey: key)
                .with(appUserID: uid).with(networkTimeout: 10).build())
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
            pendingPlan = nil; trialEligible = []
        }
        ownerID = uid
        busy = true; error = nil; message = nil
        defer {
            busy = false
            if session.userID != uid {
                access = nil; packages = []; storeAvailable = false; message = nil; error = nil
                awaitingConfirmation = false; pendingPlan = nil; trialEligible = []
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
            ProductAnalytics.identify(uid: uid, plan: result.plan.rawValue,
                                      email: session.identity?.email, name: session.identity?.displayName)
            if result.plan.rank >= (pendingPlan?.rank ?? 0) { awaitingConfirmation = false; pendingPlan = nil }
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
            let storePlan = customer.entitlements["queep_max"]?.isActive == true ? SubscriptionPlan.max
                : customer.entitlements["queep_pro"]?.isActive == true ? .pro : .free
            pendingPlan = storePlan.rank > result.plan.rank ? storePlan : nil
            awaitingConfirmation = pendingPlan != nil
            trialEligible = []
            packages = offerings.current?.availablePackages.filter {
                $0.storeProduct.productType == .autoRenewableSubscription && Self.plan($0) != nil
            } ?? []
            packages.sort { lhs, rhs in
                let l = Self.plan(lhs)?.rank ?? 0, r = Self.plan(rhs)?.rank ?? 0
                return l == r ? Self.isAnnual(lhs) && !Self.isAnnual(rhs) : l < r
            }
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: packages)
            guard session.userID == uid else { return }
            trialEligible = Set(packages.compactMap { package -> String? in
                guard let plan = Self.plan(package), plan == .pro || plan == .max,
                      Self.isAnnual(package) else { return nil }
                #if DEBUG
                // The Test Store fixture is named "yearly" and has no intro offer attached.
                // Production annual plans carry the 7-day trial this sheet is meant to sell.
                if package.storeProduct.productIdentifier == "yearly" { return package.identifier }
                #endif
                guard eligibility[package]?.status == .eligible,
                      let offer = package.storeProduct.introductoryDiscount,
                      offer.paymentMode == .freeTrial else { return nil }
                let period = offer.subscriptionPeriod
                let week = (period.unit == .day && period.value == 7)
                    || (period.unit == .week && period.value == 1)
                return week ? package.identifier : nil
            })
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
            let before = try await api.subscriptionAccess(refresh: true)
            guard session.userID == uid else { return }
            access = before
            let target = Self.plan(package)
            let upgrading = (target?.rank ?? 0) > before.plan.rank
            guard !before.active || before.isDevelopment || upgrading else {
                message = "Altere seu plano em Gerenciar na App Store para manter uma única assinatura."
                return
            }
            if let plan = Self.plan(package)?.rawValue, let period = Self.billingPeriod(package) {
                ProductAnalytics.purchaseStarted(plan: plan, period: period)
            }
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled, session.userID == uid else { return }
            pendingPlan = Self.plan(package)
            awaitingConfirmation = true
            let confirmed = try await api.subscriptionAccess(refresh: true)
            guard session.userID == uid else { return }
            access = confirmed
            awaitingConfirmation = confirmed.plan.rank < (pendingPlan?.rank ?? 1)
            ProductAnalytics.identify(uid: uid, plan: confirmed.plan.rawValue,
                                      email: session.identity?.email, name: session.identity?.displayName)
            if !awaitingConfirmation, let period = Self.billingPeriod(package) {
                ProductAnalytics.subscriptionStarted(plan: confirmed.plan.rawValue, period: period, uid: uid,
                                                     email: session.identity?.email, name: session.identity?.displayName)
            }
            message = confirmed.isDevelopment ? "Compra de teste concluída. O acesso de desenvolvimento permanece liberado."
                : !awaitingConfirmation ? "Assinatura confirmada. Ela vale também nos seus outros dispositivos."
                : "Compra recebida. Aguarde alguns segundos e toque em Atualizar assinatura para confirmar."
        }
    }

    static func plan(_ package: Package) -> SubscriptionPlan? {
        if let value = SubscriptionPlan.product(package.storeProduct.productIdentifier) { return value }
        #if DEBUG
        // Existing RevenueCat Test Store fixtures never enter a distribution build.
        if ["monthly", "yearly"].contains(package.storeProduct.productIdentifier) { return .pro }
        #endif
        return nil
    }

    static func billingPeriod(_ package: Package) -> String? {
        switch package.storeProduct.subscriptionPeriod?.unit {
        case .year: "year"
        case .month: "month"
        default: ProductEvent.billingPeriod(productIdentifier: package.storeProduct.productIdentifier)
        }
    }

    static func billingPeriod(_ customer: CustomerInfo) -> String? {
        let identifier = customer.entitlements["queep_max"]?.productIdentifier
            ?? customer.entitlements["queep_pro"]?.productIdentifier
        return identifier.flatMap { ProductEvent.billingPeriod(productIdentifier: $0) }
    }

    static func isAnnual(_ package: Package) -> Bool {
        package.storeProduct.subscriptionPeriod?.unit == .year
            && package.storeProduct.subscriptionPeriod?.value == 1
    }

    /// An active Pro trial upgrades to Max at the Max price. It does not start a second free trial.
    func offersTrial(_ package: Package) -> Bool {
        guard trialEligible.contains(package.identifier) else { return false }
        if let access, access.active, !access.isDevelopment, access.plan != .free { return false }
        return true
    }

    func package(plan: SubscriptionPlan, annual: Bool) -> Package? {
        packages.first { Self.plan($0) == plan && Self.isAnnual($0) == annual }
    }

    func preferredPackage(plan: SubscriptionPlan, annual: Bool) -> Package? {
        package(plan: plan, annual: annual) ?? packages.first { Self.plan($0) == plan }
    }

    func annualDiscount(_ package: Package) -> Int? {
        guard Self.isAnnual(package), let monthly = packages.first(where: {
            Self.plan($0) == Self.plan(package) && $0.storeProduct.subscriptionPeriod?.unit == .month
                && $0.storeProduct.subscriptionPeriod?.value == 1
                && $0.storeProduct.currencyCode == package.storeProduct.currencyCode
        }) else { return nil }
        let year = NSDecimalNumber(decimal: package.storeProduct.price).doubleValue
        let month = NSDecimalNumber(decimal: monthly.storeProduct.price).doubleValue
        guard month > 0, year < month * 12 else { return nil }
        return Int(((1 - year / (month * 12)) * 100).rounded(.down))
    }

    func restore(_ session: Session) async {
        await perform(session) { uid, api in
            try await prepare(uid)
            guard session.userID == uid else { throw QueepError.unauthorized }
            let customer = try await Purchases.shared.restorePurchases()
            guard session.userID == uid else { return }
            pendingPlan = customer.entitlements["queep_max"]?.isActive == true ? .max
                : customer.entitlements["queep_pro"]?.isActive == true ? .pro : nil
            awaitingConfirmation = pendingPlan != nil
            let confirmed = try await api.subscriptionAccess(refresh: true)
            guard session.userID == uid else { return }
            access = confirmed
            awaitingConfirmation = confirmed.plan.rank < (pendingPlan?.rank ?? 0)
            ProductAnalytics.identify(uid: uid, plan: confirmed.plan.rawValue,
                                      email: session.identity?.email, name: session.identity?.displayName)
            if !awaitingConfirmation, let period = Self.billingPeriod(customer) {
                ProductAnalytics.subscriptionStarted(plan: confirmed.plan.rawValue, period: period, uid: uid,
                                                     email: session.identity?.email, name: session.identity?.displayName)
            }
            message = confirmed.isDevelopment ? "Restauração solicitada na loja de teste."
                : confirmed.active ? "Sua assinatura está ativa nesta conta."
                : "Nenhuma assinatura ativa confirmada. Confira a conta da App Store e tente atualizar em instantes."
        }
    }
}
