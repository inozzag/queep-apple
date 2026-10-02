import Testing
@testable import QueepCore

@Test func phoneKeepsALeadingPlusAndDropsSeparators() {
    #expect(OnboardingAnswers.phone("+55 (11) 98888-7777") == "+5511988887777")
    #expect(OnboardingAnswers.phone("11 98888-7777") == "+5511988887777")
    #expect(OnboardingAnswers.phone("(11) 3333-4444") == "+551133334444")
    #expect(OnboardingAnswers.phone("+351 912 345 678") == "+351912345678")
    #expect(OnboardingAnswers.phone("89232123") == nil)
    #expect(OnboardingAnswers.phone("123") == nil)
    #expect(OnboardingAnswers.phone("1234567890123456") == nil)
    #expect(PhoneNumber.format(national: "11988887777", country: .brazil) == "(11) 98888-7777")
    #expect(PhoneNumber.format(national: "89232123", country: .brazil) == "(89) 2321-23")
    #expect(PhoneNumber.areaCodeIsKnown("00") == false)
    #expect(PhoneNumber.areaCodeIsKnown("11") == true)
}

@Test func firstSaveLinkAcceptsAHostWithoutAScheme() {
    #expect(OnboardingAnswers.link("instagram.com/queep") == "https://instagram.com/queep")
    #expect(OnboardingAnswers.link("https://x.com/queep/status/1") == "https://x.com/queep/status/1")
    #expect(OnboardingAnswers.link("nota solta") == nil)
}
