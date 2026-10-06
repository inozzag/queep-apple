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
    /// Packages whose introductory offer this account can still redeem, free or paid.
    private(set) var introEligible: Set<String> = []
    /// Optional launch messaging from the offering's metadata (`launch_label`, `launch_ends_at`).
    private(set) var launchLabel: String?
    private(set) var launchEndsAt: Date?
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
        pendingPlan = nil; trialEligible = []; clearOffers()
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
            pendingPlan = nil; trialEligible = []; clearOffers()
        }
        ownerID = uid
        busy = true; error = nil; message = nil
        defer {
            busy = false
            if session.userID != uid {
                access = nil; packages = []; storeAvailable = false; message = nil; error = nil
                awaitingConfirmation = false; pendingPlan = nil; trialEligible = []; clearOffers()
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
        #if DEBUG
        if Self.previewSample {
            applySample()
            return
        }
        #endif
        await perform(session) { uid, api in
            let result = try await api.subscriptionAccess(refresh: refresh)
            guard session.userID == uid else { return }
            access = result
            ProductAnalytics.identify(uid: uid, plan: result.plan.rawValue)
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
            clearOffers()
            if let current = offerings.current {
                let label: String = current.getMetadataValue(for: "launch_label", default: "")
                let ends: String = current.getMetadataValue(for: "launch_ends_at", default: "")
                launchLabel = label.isEmpty ? nil : label
                launchEndsAt = ISO8601DateFormatter().date(from: ends)
            }
            packages = offerings.current?.availablePackages.filter {
                $0.storeProduct.productType == .autoRenewableSubscription && Self.plan($0) != nil
            } ?? []
            packages.sort { lhs, rhs in
                let l = Self.plan(lhs)?.rank ?? 0, r = Self.plan(rhs)?.rank ?? 0
                return l == r ? Self.isAnnual(lhs) && !Self.isAnnual(rhs) : l < r
            }
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: packages)
            guard session.userID == uid else { return }
            introEligible = Set(packages.filter { eligibility[$0]?.status == .eligible }.map(\.identifier))
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

    /// True when the store charged and the API already confirms the plan.
    @discardableResult
    func purchase(_ package: Package, session: Session) async -> Bool {
        var confirmedPurchase = false
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
            ProductAnalytics.identify(uid: uid, plan: confirmed.plan.rawValue)
            if !awaitingConfirmation, let period = Self.billingPeriod(package) {
                ProductAnalytics.subscriptionStarted(plan: confirmed.plan.rawValue, period: period, uid: uid)
            }
            message = confirmed.isDevelopment ? "Compra de teste concluída. O acesso de desenvolvimento permanece liberado."
                : !awaitingConfirmation ? "Assinatura confirmada. Ela vale também nos seus outros dispositivos."
                : "Compra recebida. Aguarde alguns segundos e toque em Atualizar assinatura para confirmar."
            confirmedPurchase = !awaitingConfirmation
        }
        return confirmedPurchase
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

    /// What every paywall in the journey sells during launch: Max, billed yearly.
    var journeyPackage: Package? {
        if let package = preferredPackage(plan: .max, annual: true) { return package }
        #if DEBUG
        // The Test Store has no Max products. Its yearly fixture stands in, so the sheet and the
        // purchase can be exercised against the emulators.
        return packages.first { $0.storeProduct.productIdentifier == "yearly" }
        #else
        return nil
        #endif
    }

    /// A paid introductory price on the yearly plan, shown as the launch price.
    /// It comes from the store, so the sheet never promises a discount the purchase will not apply.
    /// The offering's metadata only adds a label and the day the promotion ends.
    func launchOffer(_ package: Package, now: Date = .now) -> LaunchOffer? {
        let product = package.storeProduct
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-launch-offer") {
            let price = product.price * Decimal(string: "0.7")!
            return LaunchOffer(label: "Preço de lançamento",
                               price: Self.format(price, product) ?? product.localizedPriceString,
                               perMonth: Self.format(price / 12, product), percent: 30, years: 1,
                               endsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600))
        }
        #endif
        guard Self.isAnnual(package), introEligible.contains(package.identifier),
              let intro = product.introductoryDiscount, intro.paymentMode != .freeTrial,
              intro.subscriptionPeriod.unit == .year, intro.subscriptionPeriod.value == 1,
              intro.price < product.price, product.price > 0 else { return nil }
        if let access, access.active, !access.isDevelopment, access.plan != .free { return nil }
        let saved = NSDecimalNumber(decimal: 1 - intro.price / product.price).doubleValue
        return LaunchOffer(label: launchLabel ?? "Preço de lançamento",
                           price: intro.localizedPriceString,
                           perMonth: Self.format(intro.price / 12, product),
                           percent: Int((saved * 100).rounded(.down)),
                           years: max(1, intro.numberOfPeriods),
                           endsAt: launchEndsAt.flatMap { $0 > now ? $0 : nil })
    }

    private static func format(_ amount: Decimal, _ product: StoreProduct) -> String? {
        product.priceFormatter?.string(from: NSDecimalNumber(decimal: amount))
    }

    private func clearOffers() {
        introEligible = []; launchLabel = nil; launchEndsAt = nil
    }

    #if DEBUG
    /// `--preview-paywall-sample`: the Brazilian launch prices with no store and no session,
    /// to review the sheet on a machine where the emulators are not running. Nothing can be bought.
    static let previewSample = ProcessInfo.processInfo.arguments.contains("--preview-paywall-sample")

    private func applySample() {
        func package(_ id: String, _ product: String, _ price: Decimal, _ text: String,
                     _ unit: SubscriptionPeriod.Unit) -> Package {
            let sample = TestStoreProduct(
                localizedTitle: "Queep Max", price: price, currencyCode: "BRL", localizedPriceString: text,
                productIdentifier: product, productType: .autoRenewableSubscription,
                localizedDescription: "", subscriptionGroupIdentifier: "preview",
                subscriptionPeriod: SubscriptionPeriod(value: 1, unit: unit),
                locale: Locale(identifier: "pt_BR"))
            return Package(identifier: id, packageType: .custom, storeProduct: sample.toStoreProduct(),
                           offeringIdentifier: "preview", webCheckoutUrl: nil)
        }
        packages = [
            package("max_yearly", "app.queep.max.yearly", Decimal(string: "999.90")!, "R$ 999,90", .year),
            package("max_monthly", "app.queep.max.monthly", Decimal(string: "129.90")!, "R$ 129,90", .month)
        ]
        // A Free account, so the sheet can show how each quota compares.
        let free = #"{"mode":"required","active":false,"expires_at":null,"will_renew":false,"checked_at":"2026-10-06T12:00:00.000Z","plan":"free","features":{"spaces":false,"media_av":false},"limits":{"operations":12,"searches":8,"items":100,"spaces":0}}"#
        access = try? APIClient.decoder().decode(SubscriptionAccess.self, from: Data(free.utf8))
        storeAvailable = true
    }
    #endif

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
            ProductAnalytics.identify(uid: uid, plan: confirmed.plan.rawValue)
            if !awaitingConfirmation, let period = Self.billingPeriod(customer) {
                ProductAnalytics.subscriptionStarted(plan: confirmed.plan.rawValue, period: period, uid: uid)
            }
            message = confirmed.isDevelopment ? "Restauração solicitada na loja de teste."
                : confirmed.active ? "Sua assinatura está ativa nesta conta."
                : "Nenhuma assinatura ativa confirmada. Confira a conta da App Store e tente atualizar em instantes."
        }
    }
}

/// The yearly plan at its launch price. `price` is what the store charges for each of the
/// first `years`; after that the plan renews at its regular price.
struct LaunchOffer: Equatable {
    let label: String
    let price: String
    let perMonth: String?
    let percent: Int?
    let years: Int
    let endsAt: Date?
}
