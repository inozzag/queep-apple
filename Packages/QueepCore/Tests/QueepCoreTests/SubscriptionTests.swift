import Foundation
import XCTest
@testable import QueepCore

final class SubscriptionContractTests: XCTestCase {
    func testAccessUsesServerPlanFeaturesAndLimits() throws {
        for plan in ["free", "pro", "max"] {
            let json = """
            {"mode":"required","active":\(plan != "free"),"checked_at":"2026-09-21T00:00:00Z",
             "expires_at":null,"will_renew":false,"plan":"\(plan)",
             "features":{"spaces":\(plan != "free"),"media_av":\(plan == "max")},
             "limits":{"operations":12,"spaces":0}}
            """
            let access = try APIClient.decoder().decode(SubscriptionAccess.self, from: Data(json.utf8))
            XCTAssertEqual(access.plan.rawValue, plan)
            XCTAssertEqual(access.features.mediaAv, plan == "max")
            XCTAssertEqual(access.limits["operations"], 12)
            XCTAssertFalse(access.isDevelopment)
        }
    }

    func testQuotaErrorPreservesUpgradeAndReset() throws {
        let json = """
        {"code":"plan_limit","message":"Limite atingido","plan":"pro","resource":"operations",
         "required_plan":"max","resets_at":"2026-10-01T00:00:00+00:00"}
        """
        let limit = try APIClient.decoder().decode(PlanRequirement.self, from: Data(json.utf8))
        XCTAssertEqual(limit.requiredPlan, .max)
        XCTAssertNotNil(limit.resetsAt)
        XCTAssertEqual(QueepError.planRequired(limit).localizedDescription, "Limite atingido")
        let max = json.replacingOccurrences(of: "\"required_plan\":\"max\"", with: "\"required_plan\":null")
        XCTAssertNil(try APIClient.decoder().decode(PlanRequirement.self, from: Data(max.utf8)).requiredPlan)
    }

    func testProductMappingRejectsUnknownProducts() {
        XCTAssertEqual(SubscriptionPlan.product("app.queep.pro.yearly"), .pro)
        XCTAssertEqual(SubscriptionPlan.product("app.queep.max.monthly"), .max)
        for period in ["monthly", "yearly"] {
            XCTAssertEqual(SubscriptionPlan.product("app.queep.mac.pro.\(period)"), .pro)
            XCTAssertEqual(SubscriptionPlan.product("app.queep.mac.max.\(period)"), .max)
        }
        XCTAssertNil(SubscriptionPlan.product("app.queep.team.yearly"))
        XCTAssertNil(SubscriptionPlan.product("monthly"))
        XCTAssertEqual(PlanRequirement.media(for: .pro).requiredPlan, .max)
    }

    func testMonthlyUsageIncludesPersistentInventory() throws {
        let json = """
        {"plan":"free","resets_at":"2026-10-01T00:00:00Z",
         "counters":{"operations":{"used":12,"limit":12},"storage_bytes":{"used":400,"limit":500}}}
        """
        let usage = try APIClient.decoder().decode(Usage.self, from: Data(json.utf8))
        XCTAssertEqual(usage.plan, .free)
        XCTAssertEqual(usage.counters["operations"]?.used, 12)
        XCTAssertEqual(usage.counters["storage_bytes"]?.limit, 500)
    }

    func testProToMaxUpgradePurchasesInTheApp() throws {
        let pro = try Self.access(plan: "pro", active: true)
        XCTAssertFalse(SubscriptionCheckout.managesInAppStore(access: pro, packagePlan: .max))
        XCTAssertTrue(SubscriptionCheckout.managesInAppStore(access: pro, packagePlan: .pro))
    }

    func testSamePlanAndDowngradeStayOnApple() throws {
        let max = try Self.access(plan: "max", active: true)
        XCTAssertTrue(SubscriptionCheckout.managesInAppStore(access: max, packagePlan: .max))
        let pro = try Self.access(plan: "pro", active: true)
        XCTAssertTrue(SubscriptionCheckout.managesInAppStore(access: pro, packagePlan: .pro))
        XCTAssertTrue(SubscriptionCheckout.managesInAppStore(access: pro, packagePlan: .free))
    }

    func testInactiveAndDevelopmentAccountsPurchaseInTheApp() throws {
        XCTAssertFalse(SubscriptionCheckout.managesInAppStore(access: nil, packagePlan: .max))
        let lapsed = try Self.access(plan: "pro", active: false)
        XCTAssertFalse(SubscriptionCheckout.managesInAppStore(access: lapsed, packagePlan: .max))
        XCTAssertFalse(SubscriptionCheckout.managesInAppStore(access: lapsed, packagePlan: .pro))
        let development = try Self.access(plan: "max", active: true, mode: "development")
        XCTAssertFalse(SubscriptionCheckout.managesInAppStore(access: development, packagePlan: .max))
        let pro = try Self.access(plan: "pro", active: true)
        XCTAssertTrue(SubscriptionCheckout.managesInAppStore(access: pro, packagePlan: nil))
    }

    func testFirstPaywallWaitsUntilOffersAndKnownAccess() throws {
        let free = try Self.access(plan: "free", active: false)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: false, access: free), .wait)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: false, access: nil), .wait)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: true, access: nil), .wait)
        XCTAssertFalse(FirstPaywall.decide(offersLoaded: true, access: nil).rememberShown)
        XCTAssertNotEqual(FirstPaywall.decide(offersLoaded: true, access: nil),
                          FirstPaywall.decide(offersLoaded: true, access: free))
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: true, access: free), .show)
        XCTAssertTrue(FirstPaywall.decide(offersLoaded: true, access: free).rememberShown)
    }

    func testFirstPaywallSkipsKnownPayingSubscribers() throws {
        let pro = try Self.access(plan: "pro", active: true)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: true, access: pro), .skip)
        XCTAssertTrue(FirstPaywall.decide(offersLoaded: true, access: pro).rememberShown)
        let lapsed = try Self.access(plan: "pro", active: false)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: true, access: lapsed), .skip)
        let development = try Self.access(plan: "max", active: true, mode: "development")
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: false, access: development), .wait)
        XCTAssertEqual(FirstPaywall.decide(offersLoaded: true, access: development), .show)
    }

    private static func access(plan: String, active: Bool, mode: String = "required") throws -> SubscriptionAccess {
        let json = """
        {"mode":"\(mode)","active":\(active),"checked_at":"2026-09-21T00:00:00Z",
         "expires_at":null,"will_renew":false,"plan":"\(plan)",
         "features":{"spaces":false,"media_av":false},"limits":{"operations":12}}
        """
        return try APIClient.decoder().decode(SubscriptionAccess.self, from: Data(json.utf8))
    }
}
