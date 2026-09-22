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
}
