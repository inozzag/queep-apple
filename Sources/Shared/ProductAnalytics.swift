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
        config.setBeforeSend { event in
            let blocked: Set<String> = [
                "$autocapture", "$screen", "$rageclick", "$exception", "$feature_flag_called"
            ]
            return blocked.contains(event.event) ? nil : event
        }
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
        identify(uid: uid, plan: plan)
    }

    static func recordSignIn(created: Bool, method: String, session: Session) async {
        guard enabled, let uid = session.userID else { return }
        let plan = (try? await session.client()?.subscriptionAccess())?.plan.rawValue
        identify(uid: uid, plan: plan)
        guard let event = ProductEvent.auth(created: created, method: method, platform: platform) else { return }
        emit(event.name, event.properties.mapValues { $0 as Any })
    }

    static func reset() {
        guard enabled else { return }
        PostHogSDK.shared.reset()
        identifiedUID = nil
        identifiedPlan = nil
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
        guard let properties = ProductEvent.paywall(code: requirement.code, targetPlan: requirement.requiredPlan?.rawValue) else { return }
        emit("paywall_viewed", properties.mapValues { $0 as Any })
    }

    static func purchaseStarted(plan: String, period: String) {
        guard let properties = ProductEvent.purchase(plan: plan, period: period) else { return }
        emit("purchase_started", properties.mapValues { $0 as Any })
    }

    static func subscriptionStarted(plan: String, period: String, uid: String) {
        guard let properties = ProductEvent.purchase(plan: plan, period: period) else { return }
        identify(uid: uid, plan: plan)
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

    static func identify(uid: String, plan: String?) {
        guard enabled else { return }
        // PostHog ignores identify() once a person is already identified. A new account on a
        // device that still has the previous user must reset first, or account_created stays
        // on the old distinct id. An anonymous id is a UUID and should still be linked.
        let current = PostHogSDK.shared.getDistinctId()
        if current != uid, UUID(uuidString: current) == nil {
            PostHogSDK.shared.reset()
            identifiedUID = nil
            identifiedPlan = nil
            if let configuredEnvironment {
                PostHogSDK.shared.register(["environment": configuredEnvironment])
            }
        }
        let planChanged = plan != nil && plan != identifiedPlan
        guard uid != identifiedUID || planChanged else { return }
        var properties: [String: Any] = ["platform": platform]
        if let plan {
            properties["plan"] = plan
            identifiedPlan = plan
        }
        PostHogSDK.shared.identify(uid, userProperties: properties)
        identifiedUID = uid
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
