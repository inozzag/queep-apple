import Foundation
import PostHog
import QueepCore

/// Product analytics for QueepMac and QueepiOS. No-ops without a project token, and never in local Debug.
@MainActor
enum ProductAnalytics {
    private static var enabled = false
    private static var configuredEnvironment: String?
    private static var identifiedUID: String?
    private static var identifiedPlan: String?
    private static var identifiedEmail: String?
    private static var identifiedName: String?
    private static var firedShareIDs: Set<String> = []

    static var platform: String {
        #if os(iOS)
        "ios"
        #else
        "macos"
        #endif
    }

    static func start() {
        guard !enabled else { return }
        guard let environment = environment, let key = secret("QueepPostHogKey"), let host = secret("QueepPostHogHost"),
              let url = URL(string: host), url.scheme == "https", url.host != nil else { return }
        let config = PostHogConfig(projectToken: key, host: host)
        config.debug = false
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.personProfiles = .identifiedOnly
        config.errorTrackingConfig.autoCapture = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        #if os(iOS)
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.captureAutocaptureElementText = false
        config.rageClickConfig.enabled = false
        config.surveys = false
        config.sessionReplay = false
        #endif
        config.setBeforeSend(dropBlockedEvents)
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["environment": environment])
        configuredEnvironment = environment
        enabled = true
        SessionAnalytics.recordSignIn = { created, method, session in
            await recordSignIn(created: created, method: method, session: session)
        }
        SessionAnalytics.reset = { reset() }
        LibraryAnalytics.searchSubmitted = { searchSubmitted(hasResults: $0) }
        LibraryAnalytics.spaceCreated = { spaceCreated() }
    }

    static func syncIdentity(_ session: Session) async {
        guard enabled, let uid = session.userID, let api = session.client() else { return }
        let plan = (try? await api.subscriptionAccess())?.plan.rawValue
        identify(uid: uid, plan: plan, email: session.identity?.email, name: session.identity?.displayName)
    }

    static func recordSignIn(created: Bool, method: String, session: Session) async {
        guard enabled, let uid = session.userID else { return }
        let plan = (try? await session.client()?.subscriptionAccess())?.plan.rawValue
        identify(uid: uid, plan: plan, email: session.identity?.email, name: session.identity?.displayName)
        guard let event = ProductEvent.auth(created: created, method: method, platform: platform) else { return }
        emit(event.name, event.properties.mapValues { $0 as Any })
    }

    static func reset() {
        guard enabled else { return }
        PostHogSDK.shared.reset()
        identifiedUID = nil
        identifiedPlan = nil
        identifiedEmail = nil
        identifiedName = nil
        if let configuredEnvironment {
            PostHogSDK.shared.register(["environment": configuredEnvironment])
        }
    }

    static func captureSaved(kind: String, url: String?, source: String) {
        guard let properties = ProductEvent.captureSaved(kind: kind, url: url, source: source, platform: platform) else { return }
        emit("capture_saved", properties.mapValues { $0 as Any })
    }

    static func searchSubmitted(hasResults: Bool) {
        emit("search_submitted", ["has_results": hasResults])
    }

    static func referenceOpened(kind: String, url: String?) {
        emit("reference_opened", ProductEvent.referenceOpened(kind: kind, url: url).mapValues { $0 as Any })
    }

    static func spaceCreated() {
        guard let properties = ProductEvent.spaceCreated(platform: platform) else { return }
        emit("space_created", properties.mapValues { $0 as Any })
    }

    static func paywallViewed(_ requirement: PlanRequirement) {
        paywallViewed(code: requirement.code, targetPlan: requirement.requiredPlan?.rawValue)
    }

    static func paywallViewed(code: String, targetPlan: String?) {
        guard let properties = ProductEvent.paywall(code: code, targetPlan: targetPlan) else { return }
        emit("paywall_viewed", properties.mapValues { $0 as Any })
    }

    /// Journey sheet. `hook` is the `paywall_title_hook` variant actually shown (`a`...`e`).
    static func paywallViewed(reason: String, hook: String, plan: String, period: String, trialEligible: Bool) {
        emit("paywall_viewed", [
            "reason": reason,
            "hook": hook,
            "platform": platform,
            "plan": plan,
            "period": period,
            "trial_eligible": trialEligible
        ])
    }

    static func paywallPeriodToggled(period: String) {
        emit("paywall_period_toggled", ["period": period])
    }

    static func paywallAllPlansTapped() {
        emit("paywall_all_plans_tapped", [:])
    }

    static func paywallCTATapped(plan: String, period: String, trial: Bool) {
        emit("paywall_cta_tapped", ["plan": plan, "period": period, "trial": trial])
    }

    static func paywallPurchaseCompleted(plan: String, period: String) {
        emit("paywall_purchase_completed", ["plan": plan, "period": period])
    }

    static func paywallTrialStarted(plan: String, period: String) {
        emit("paywall_trial_started", ["plan": plan, "period": period])
    }

    static func paywallClosed(reason: String) {
        emit("paywall_closed", ["reason": reason])
    }

    /// Multivariate `paywall_title_hook` (`a`...`e`). Returns the cached variant immediately.
    /// Nil when analytics is off, the flag is missing, or it is not a string variant — the
    /// sheet then uses its reason default. A later reload, if it finds a variant, is applied
    /// on the main actor through `update`. The flag itself is not created here.
    static func paywallTitleHook(update: @escaping @MainActor (String) -> Void) -> String? {
        guard enabled else { return nil }
        return FeatureFlagLoad.current(
            cached: cachedPaywallHook(),
            reload: reloadPaywallFlags,
            read: cachedPaywallHook,
            update: update
        )
    }

    /// PostHog invokes this on `com.posthog.RemoteConfig`, a background queue.
    /// The completion is built in `FeatureFlagLoad`, which is not main-actor isolated.
    nonisolated private static func reloadPaywallFlags(_ completion: @escaping @Sendable () -> Void) {
        PostHogSDK.shared.reloadFeatureFlags(completion)
    }

    nonisolated private static func cachedPaywallHook() -> String? {
        flagString(PostHogSDK.shared.getFeatureFlag(paywallHookFlag, sendFeatureFlagEvent: false))
    }

    nonisolated private static let paywallHookFlag = "paywall_title_hook"

    nonisolated private static func flagString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// PostHog runs `beforeSend` on the thread that captures the event, which is not always main.
    nonisolated private static func dropBlockedEvents(_ event: PostHogEvent) -> PostHogEvent? {
        let blocked: Set<String> = [
            "$autocapture", "$screen", "$rageclick", "$exception", "$feature_flag_called"
        ]
        return blocked.contains(event.event) ? nil : event
    }

    static func purchaseStarted(plan: String, period: String) {
        guard let properties = ProductEvent.purchase(plan: plan, period: period) else { return }
        emit("purchase_started", properties.mapValues { $0 as Any })
    }

    static func subscriptionStarted(plan: String, period: String, uid: String,
                                    email: String? = nil, name: String? = nil) {
        guard let properties = ProductEvent.purchase(plan: plan, period: period) else { return }
        identify(uid: uid, plan: plan, email: email, name: name)
        emit("subscription_started", properties.mapValues { $0 as Any })
    }

    /// Confirms share-extension saves from this app. The phrase, file and URL stay out of the event.
    static func deliverSharedCaptures(_ session: Session) async {
        let pending = ShareCaptureQueue.load()
        guard !pending.isEmpty else { return }
        guard enabled, let api = session.client(), session.userID != nil else {
            if !enabled { ShareCaptureQueue.remove(ids: Set(pending.map(\.id))) }
            return
        }
        var done = Set<String>()
        for item in pending {
            if firedShareIDs.contains(item.id) { done.insert(item.id); continue }
            do {
                let reference = try await api.get(id: item.id)
                guard session.userID != nil else { return }
                firedShareIDs.insert(item.id)
                if firedShareIDs.count > 200, let oldest = firedShareIDs.first {
                    firedShareIDs.remove(oldest)
                }
                captureSaved(kind: reference.kind, url: reference.url, source: "share")
                done.insert(item.id)
            } catch is CancellationError {
                return
            } catch QueepError.unavailable {
                continue
            } catch {
                done.insert(item.id)
            }
        }
        ShareCaptureQueue.remove(ids: done)
    }

    static func identify(uid: String, plan: String?, email: String? = nil, name: String? = nil) {
        guard enabled else { return }
        // PostHog ignores identify() once a person is already identified. A new account on a
        // device that still has the previous user must reset first, or account_created stays
        // on the old distinct id. An anonymous id is a UUID and should still be linked.
        let current = PostHogSDK.shared.getDistinctId()
        if current != uid, UUID(uuidString: current) == nil {
            PostHogSDK.shared.reset()
            identifiedUID = nil
            identifiedPlan = nil
            identifiedEmail = nil
            identifiedName = nil
            if let configuredEnvironment {
                PostHogSDK.shared.register(["environment": configuredEnvironment])
            }
        }
        let person = ProductEvent.person(platform: platform, email: email, name: name, plan: plan)
        let planChanged = person["plan"] != nil && person["plan"] != identifiedPlan
        let emailChanged = person["email"] != nil && person["email"] != identifiedEmail
        let nameChanged = person["name"] != nil && person["name"] != identifiedName
        guard uid != identifiedUID || planChanged || emailChanged || nameChanged else { return }
        PostHogSDK.shared.identify(uid, userProperties: person.mapValues { $0 as Any })
        identifiedUID = uid
        if let plan = person["plan"] { identifiedPlan = plan }
        if let email = person["email"] { identifiedEmail = email }
        if let name = person["name"] { identifiedName = name }
    }

    private static func emit(_ name: String, _ properties: [String: Any]) {
        guard enabled else { return }
        PostHogSDK.shared.capture(name, properties: properties)
        PostHogSDK.shared.flush()
    }

    private static var environment: String? {
        #if DEBUG && QUEEP_CLOUD
        "development"
        #elseif QUEEP_CLOUD
        "testflight"
        #else
        nil
        #endif
    }

    private static func secret(_ name: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: name) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.count > 8, !value.contains("$("), !value.contains(" ") else { return nil }
        return value
    }
}
