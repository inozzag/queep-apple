import Testing
@testable import QueepCore

@Test func phoneKeepsALeadingPlusAndDropsSeparators() {
    #expect(OnboardingAnswers.phone("+55 (11) 98888-7777") == "+5511988887777")
    #expect(OnboardingAnswers.phone("11 98888-7777") == "11988887777")
    #expect(OnboardingAnswers.phone("123") == nil)
    #expect(OnboardingAnswers.phone("1234567890123456") == nil)
}

@Test func firstSaveLinkAcceptsAHostWithoutAScheme() {
    #expect(OnboardingAnswers.link("instagram.com/queep") == "https://instagram.com/queep")
    #expect(OnboardingAnswers.link("https://x.com/queep/status/1") == "https://x.com/queep/status/1")
    #expect(OnboardingAnswers.link("nota solta") == nil)
}
