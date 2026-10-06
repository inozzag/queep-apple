import Testing
@testable import QueepCore

@Test func captureSavedOmitsNoteTextUrlAndQuery() {
    let note = ProductEvent.captureSaved(kind: "note", url: nil, source: "library", platform: "ios")
    #expect(note == ["kind": "note", "source": "library", "platform": "ios"])

    let social = ProductEvent.captureSaved(
        kind: "link", url: "https://x.com/ada/status/1", source: "share", platform: "ios")
    #expect(social == ["kind": "social", "source": "share", "platform": "ios"])
    #expect(social?.values.contains("https://x.com/ada/status/1") == false)

    let site = ProductEvent.captureSaved(
        kind: "link", url: "https://cursor.com", source: "paste", platform: "macos")
    #expect(site?["kind"] == "link")
    #expect(ProductEvent.captureSaved(kind: "video", url: nil, source: "drag", platform: "macos")?["kind"] == "video")
    #expect(ProductEvent.captureSaved(kind: "audio", url: nil, source: "shortcut", platform: "macos")?["kind"] == "audio")
    #expect(ProductEvent.captureSaved(kind: "note", url: nil, source: "clipboard", platform: "ios") == nil)
}

@Test func authEventDistinguishesCreationFromExistingAccount() {
    let created = ProductEvent.auth(created: true, method: "email", platform: "ios")
    #expect(created?.name == "account_created")
    #expect(created?.properties == ["method": "email", "platform": "ios"])

    let returning = ProductEvent.auth(created: false, method: "apple", platform: "macos")
    #expect(returning?.name == "sign_in_completed")
    #expect(returning?.properties["method"] == "apple")
    #expect(ProductEvent.auth(created: true, method: "password", platform: "ios") == nil)
}

@Test func identifyPersonKeepsAuthEmailNameAndPlanOnly() {
    let person = ProductEvent.person(platform: "ios", email: " ada@example.com ", name: " Ada ", plan: "pro")
    #expect(person == ["platform": "ios", "email": "ada@example.com", "name": "Ada", "plan": "pro"])

    #expect(ProductEvent.person(platform: "macos", email: " ", name: "", plan: nil) == ["platform": "macos"])
    let rejected = ProductEvent.person(platform: "ios", email: "not-an-email", name: "Nome", plan: "enterprise")
    #expect(rejected["email"] == nil)
    #expect(rejected["plan"] == nil)
    #expect(rejected["name"] == "Nome")
    #expect(ProductEvent.person(platform: "ios", email: "a@b.co", name: "Nome", plan: "free")["plan"] == "free")
    #expect(ProductEvent.auth(created: false, method: "apple", platform: "ios")?.properties["email"] == nil)
}

@Test func searchAndPaywallPropertiesStayWithinTheContract() {
    #expect(ProductEvent.searchSubmitted(hasResults: false) == ["has_results": false])
    #expect(ProductEvent.searchSubmitted(hasResults: true) == ["has_results": true])
    #expect(ProductEvent.paywall(code: "spaces_required", targetPlan: "pro") == [
        "reason": "spaces_required", "target_plan": "pro"
    ])
    #expect(ProductEvent.paywall(code: "media_av_required", targetPlan: nil)?["target_plan"] == "none")
    #expect(ProductEvent.paywall(code: "first_save", targetPlan: "pro")?["reason"] == "first_save")
    #expect(ProductEvent.paywall(code: "not_a_wall", targetPlan: "max") == nil)
    #expect(ProductEvent.referenceOpened(kind: "image", url: nil) == ["kind": "image"])
    #expect(ProductEvent.spaceCreated(platform: "macos") == ["platform": "macos"])
    #expect(ProductEvent.purchase(plan: "pro", period: "year") == ["plan": "pro", "period": "year"])
    #expect(ProductEvent.purchase(plan: "free", period: "month") == nil)
    #expect(ProductEvent.billingPeriod(productIdentifier: "app.queep.pro.yearly") == "year")
    #expect(ProductEvent.billingPeriod(productIdentifier: "app.queep.max.monthly") == "month")
    #expect(ProductEvent.billingPeriod(productIdentifier: "unknown") == nil)
}
