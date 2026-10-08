import XCTest
@testable import QueepCore

final class PaywallCopyTests: XCTestCase {
    func testHookTitlesMatchTheFiveVariants() {
        XCTAssertEqual(PaywallHook.a.title, "Crie seu segundo cérebro de referências")
        XCTAssertEqual(PaywallHook.b.title, "Continue construindo seu segundo cérebro")
        XCTAssertEqual(PaywallHook.c.title, "Ache qualquer referência em segundos")
        XCTAssertEqual(PaywallHook.d.title, "Pare de perder o que você salva")
        XCTAssertEqual(PaywallHook.e.title, "Transforme horas de feed em referências pro seu trabalho")
    }

    func testBadgeFollowsTheReasonAndResource() {
        XCTAssertEqual(PaywallCopy.badge(reason: "first_save", resource: nil), "Faça seu primeiro save")
        XCTAssertEqual(PaywallCopy.badge(reason: "onboarding", resource: nil), "Faça seu primeiro save")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "operations"), "Seu limite de imagens acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "images"), "Seu limite de imagens acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "items"), "Seu limite de itens acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "links"), "Seu limite de itens acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "searches"), "Suas buscas do mês acabaram")
        XCTAssertEqual(PaywallCopy.badge(reason: "storage_limit", resource: "storage_bytes"), "Seu espaço acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "storage_bytes"), "Seu espaço acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "spaces"), "Seu limite de Spaces acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "spaces_required", resource: nil), "Seu limite de Spaces acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "media_av_required", resource: "media_av"), "Vídeo e áudio são do Queep Max")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "media_seconds"), "Vídeo e áudio são do Queep Max")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: "upload_bytes"), "Seu limite de envio acabou")
        XCTAssertEqual(PaywallCopy.badge(reason: "plan_limit", resource: nil), "Seu limite acabou")
        XCTAssertNil(PaywallCopy.badge(reason: "ajustes", resource: nil))
        XCTAssertNil(PaywallCopy.badge(reason: "settings", resource: nil))
        XCTAssertNil(PaywallCopy.badge(reason: "preview", resource: "operations"))
        XCTAssertNil(PaywallCopy.badge(reason: "something_else", resource: nil))
    }

    func testDefaultHookFollowsTheReason() {
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "first_save", resource: nil), .a)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "onboarding", resource: nil), .a)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "plan_limit", resource: "operations"), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "plan_limit", resource: "items"), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "plan_limit", resource: "searches"), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "storage_limit", resource: "storage_bytes"), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "plan_limit", resource: "spaces"), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "spaces_required", resource: nil), .b)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "media_av_required", resource: "media_av"), .c)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "plan_limit", resource: "media_av"), .c)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "ajustes", resource: nil), .c)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "settings", resource: nil), .c)
        XCTAssertEqual(PaywallCopy.defaultHook(reason: "preview", resource: nil), .c)
    }

    func testFlagOverridesTheDefaultHook() {
        XCTAssertEqual(PaywallCopy.hook(flag: "a", reason: "plan_limit", resource: "spaces"), .a)
        XCTAssertEqual(PaywallCopy.hook(flag: "B", reason: "first_save", resource: nil), .b)
        XCTAssertEqual(PaywallCopy.hook(flag: " c ", reason: "first_save", resource: nil), .c)
        XCTAssertEqual(PaywallCopy.hook(flag: "d", reason: "media_av_required", resource: "media_av"), .d)
        XCTAssertEqual(PaywallCopy.hook(flag: "e", reason: "ajustes", resource: nil), .e)
        XCTAssertEqual(PaywallCopy.hook(flag: nil, reason: "first_save", resource: nil), .a)
        XCTAssertEqual(PaywallCopy.hook(flag: "nope", reason: "plan_limit", resource: "items"), .b)
        XCTAssertEqual(PaywallCopy.hook(flag: "", reason: "media_av_required", resource: nil), .c)
    }

    func testJourneySellsProUnlessTheWallIsMediaOrRequiresMax() {
        XCTAssertEqual(PaywallCopy.offeredPlan(reason: "first_save", resource: nil, requiredPlan: nil), .pro)
        XCTAssertEqual(PaywallCopy.offeredPlan(reason: "plan_limit", resource: "spaces", requiredPlan: .pro), .pro)
        XCTAssertEqual(PaywallCopy.offeredPlan(reason: "plan_limit", resource: "searches", requiredPlan: .max), .max)
        XCTAssertEqual(PaywallCopy.offeredPlan(reason: "media_av_required", resource: "media_av", requiredPlan: .max), .max)
        XCTAssertEqual(PaywallCopy.offeredPlan(reason: "media_av_required", resource: "media_av", requiredPlan: nil), .max)
        XCTAssertEqual(PaywallCopy.subtitle(for: .pro), PaywallCopy.proSubtitle)
        XCTAssertEqual(PaywallCopy.subtitle(for: .max), PaywallCopy.maxSubtitle)
        XCTAssertEqual(PaywallCopy.benefits(for: .pro).count, 4)
        XCTAssertEqual(PaywallCopy.benefits(for: .max).map(\.text), [
            "Tudo do Pro, com espaço de sobra",
            "Vídeos e áudios transcritos e resumidos",
            "Busque dentro do que foi dito no vídeo"
        ])
    }

    func testAnnualDiscountRoundsDownAndHidesWhenNotCheaper() {
        XCTAssertEqual(
            PaywallPricing.annualDiscountPercent(yearly: decimal("249.90"), monthly: decimal("29.90")),
            30)
        XCTAssertEqual(
            PaywallPricing.annualDiscountPercent(yearly: decimal("90"), monthly: decimal("10")),
            25)
        XCTAssertEqual(
            PaywallPricing.annualDiscountPercent(yearly: decimal("82.92"), monthly: decimal("10")),
            30)
        XCTAssertEqual(
            PaywallPricing.annualDiscountPercent(yearly: decimal("100.10"), monthly: decimal("10")),
            16)
        XCTAssertNil(PaywallPricing.annualDiscountPercent(yearly: decimal("120"), monthly: decimal("10")))
        XCTAssertNil(PaywallPricing.annualDiscountPercent(yearly: decimal("130"), monthly: decimal("10")))
        XCTAssertNil(PaywallPricing.annualDiscountPercent(yearly: decimal("100"), monthly: decimal("0")))
        XCTAssertNil(PaywallPricing.annualDiscountPercent(yearly: decimal("0"), monthly: decimal("10")))
    }

    func testCallToActionUsesTheRealTrialLength() {
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .pro, trialDays: 7), "Começar 7 dias grátis")
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .pro, trialDays: 1), "Começar 1 dia grátis")
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .max, trialDays: 14), "Começar 14 dias grátis")
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .pro, trialDays: nil), "Assinar Queep Pro")
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .max, trialDays: nil), "Assinar Queep Max")
        XCTAssertEqual(PaywallOfferCopy.callToAction(plan: .pro, trialDays: 0), "Assinar Queep Pro")
    }

    func testPriceLineLeadsWithTheBilledAmount() {
        let year = PaywallOfferCopy.priceLine(
            price: "R$ 249,90", period: .year, trialDays: nil, monthlyEquivalent: "R$ 20,83")
        XCTAssertEqual(year.primary, "R$ 249,90 por ano")
        XCTAssertEqual(year.secondary, "equivale a R$ 20,83 por mês")

        let trial = PaywallOfferCopy.priceLine(
            price: "R$ 249,90", period: .year, trialDays: 7, monthlyEquivalent: "R$ 20,83")
        XCTAssertEqual(trial.primary, "Grátis por 7 dias, depois R$ 249,90 por ano")
        XCTAssertEqual(trial.secondary, "equivale a R$ 20,83 por mês")

        let oneDay = PaywallOfferCopy.priceLine(
            price: "R$ 29,90", period: .month, trialDays: 1, monthlyEquivalent: "R$ 29,90")
        XCTAssertEqual(oneDay.primary, "Grátis por 1 dia, depois R$ 29,90 por mês")
        XCTAssertNil(oneDay.secondary)

        let month = PaywallOfferCopy.priceLine(
            price: "R$ 29,90", period: .month, trialDays: nil, monthlyEquivalent: nil)
        XCTAssertEqual(month.primary, "R$ 29,90 por mês")
        XCTAssertNil(month.secondary)
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text)!
    }
}
