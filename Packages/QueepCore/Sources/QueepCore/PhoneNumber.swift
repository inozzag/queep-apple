import Foundation

/// Country calling code and the national number, checked before it is stored.
public struct PhoneCountry: Identifiable, Hashable, Sendable {
    public let iso: String
    public let name: String
    public let dial: String
    public let nationalRange: ClosedRange<Int>

    public var id: String { iso }
    public var flag: String { PhoneNumber.flag(for: iso) }
    public var dialLabel: String { "+\(dial)" }

    public static let brazil = PhoneNumber.countries[0]
}

public enum PhoneNumber {
    public static let countries: [PhoneCountry] = [
        PhoneCountry(iso: "BR", name: "Brasil", dial: "55", nationalRange: 10...11),
        PhoneCountry(iso: "PT", name: "Portugal", dial: "351", nationalRange: 9...9),
        PhoneCountry(iso: "US", name: "Estados Unidos", dial: "1", nationalRange: 10...10),
        PhoneCountry(iso: "CA", name: "Canadá", dial: "1", nationalRange: 10...10),
        PhoneCountry(iso: "AR", name: "Argentina", dial: "54", nationalRange: 10...10),
        PhoneCountry(iso: "MX", name: "México", dial: "52", nationalRange: 10...10),
        PhoneCountry(iso: "CL", name: "Chile", dial: "56", nationalRange: 9...9),
        PhoneCountry(iso: "CO", name: "Colômbia", dial: "57", nationalRange: 10...10),
        PhoneCountry(iso: "UY", name: "Uruguai", dial: "598", nationalRange: 8...8),
        PhoneCountry(iso: "PY", name: "Paraguai", dial: "595", nationalRange: 9...9),
        PhoneCountry(iso: "PE", name: "Peru", dial: "51", nationalRange: 9...9),
        PhoneCountry(iso: "BO", name: "Bolívia", dial: "591", nationalRange: 8...8),
        PhoneCountry(iso: "EC", name: "Equador", dial: "593", nationalRange: 9...9),
        PhoneCountry(iso: "VE", name: "Venezuela", dial: "58", nationalRange: 10...10),
        PhoneCountry(iso: "GB", name: "Reino Unido", dial: "44", nationalRange: 10...10),
        PhoneCountry(iso: "IE", name: "Irlanda", dial: "353", nationalRange: 9...9),
        PhoneCountry(iso: "FR", name: "França", dial: "33", nationalRange: 9...9),
        PhoneCountry(iso: "DE", name: "Alemanha", dial: "49", nationalRange: 10...11),
        PhoneCountry(iso: "ES", name: "Espanha", dial: "34", nationalRange: 9...9),
        PhoneCountry(iso: "IT", name: "Itália", dial: "39", nationalRange: 9...10),
        PhoneCountry(iso: "NL", name: "Países Baixos", dial: "31", nationalRange: 9...9),
        PhoneCountry(iso: "BE", name: "Bélgica", dial: "32", nationalRange: 9...9),
        PhoneCountry(iso: "CH", name: "Suíça", dial: "41", nationalRange: 9...9),
        PhoneCountry(iso: "AT", name: "Áustria", dial: "43", nationalRange: 10...10),
        PhoneCountry(iso: "SE", name: "Suécia", dial: "46", nationalRange: 9...9),
        PhoneCountry(iso: "NO", name: "Noruega", dial: "47", nationalRange: 8...8),
        PhoneCountry(iso: "DK", name: "Dinamarca", dial: "45", nationalRange: 8...8),
        PhoneCountry(iso: "FI", name: "Finlândia", dial: "358", nationalRange: 9...9),
        PhoneCountry(iso: "PL", name: "Polônia", dial: "48", nationalRange: 9...9),
        PhoneCountry(iso: "JP", name: "Japão", dial: "81", nationalRange: 10...10),
        PhoneCountry(iso: "KR", name: "Coreia do Sul", dial: "82", nationalRange: 9...10),
        PhoneCountry(iso: "CN", name: "China", dial: "86", nationalRange: 11...11),
        PhoneCountry(iso: "IN", name: "Índia", dial: "91", nationalRange: 10...10),
        PhoneCountry(iso: "AU", name: "Austrália", dial: "61", nationalRange: 9...9),
        PhoneCountry(iso: "NZ", name: "Nova Zelândia", dial: "64", nationalRange: 8...10),
        PhoneCountry(iso: "ZA", name: "África do Sul", dial: "27", nationalRange: 9...9),
        PhoneCountry(iso: "AE", name: "Emirados Árabes", dial: "971", nationalRange: 9...9),
        PhoneCountry(iso: "IL", name: "Israel", dial: "972", nationalRange: 9...9),
        PhoneCountry(iso: "TR", name: "Turquia", dial: "90", nationalRange: 10...10),
        PhoneCountry(iso: "AO", name: "Angola", dial: "244", nationalRange: 9...9),
        PhoneCountry(iso: "MZ", name: "Moçambique", dial: "258", nationalRange: 9...9),
        PhoneCountry(iso: "CV", name: "Cabo Verde", dial: "238", nationalRange: 7...7),
        PhoneCountry(iso: "GW", name: "Guiné-Bissau", dial: "245", nationalRange: 7...7)
    ]

    /// ANATEL area codes. 55 is a DDD in Rio Grande do Sul and also Brazil's country code.
    public static let brazilAreaCodes: Set<String> = [
        "11", "12", "13", "14", "15", "16", "17", "18", "19",
        "21", "22", "24", "27", "28",
        "31", "32", "33", "34", "35", "37", "38",
        "41", "42", "43", "44", "45", "46", "47", "48", "49",
        "51", "53", "54", "55",
        "61", "62", "63", "64", "65", "66", "67", "68", "69",
        "71", "73", "74", "75", "77", "79",
        "81", "82", "83", "84", "85", "86", "87", "88", "89",
        "91", "92", "93", "94", "95", "96", "97", "98", "99"
    ]

    public static var deviceCountry: PhoneCountry {
        let code = Locale.current.region?.identifier ?? "BR"
        return countries.first { $0.iso == code } ?? .brazil
    }

    public static func flag(for iso: String) -> String {
        iso.uppercased().unicodeScalars.compactMap { scalar -> String? in
            guard (65...90).contains(scalar.value),
                  let regional = UnicodeScalar(127397 + scalar.value) else { return nil }
            return String(regional)
        }.joined()
    }

    public static func nationalDigits(_ raw: String, country: PhoneCountry) -> String {
        String(raw.filter(\.isNumber).prefix(country.nationalRange.upperBound))
    }

    /// `(11) 98888-7777` in Brazil. Other countries are grouped in threes.
    public static func format(national raw: String, country: PhoneCountry) -> String {
        let digits = nationalDigits(raw, country: country)
        if country.iso == "BR" { return formatBrazil(digits) }
        return formatGroups(digits)
    }

    /// `+5511988887777` when the national number matches that country. Otherwise nil.
    public static func e164(national raw: String, country: PhoneCountry) -> String? {
        let digits = nationalDigits(raw, country: country)
        guard isValid(national: digits, country: country) else { return nil }
        return "+\(country.dial)\(digits)"
    }

    public static func isValid(national digits: String, country: PhoneCountry) -> Bool {
        guard country.nationalRange.contains(digits.count) else { return false }
        if country.iso == "BR" { return isValidBrazil(digits) }
        return true
    }

    public static func areaCodeIsKnown(_ code: String) -> Bool {
        brazilAreaCodes.contains(code)
    }

    /// Splits a stored draft or a typed international number into country plus national digits.
    public static func parts(from stored: String) -> (PhoneCountry, String) {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = trimmed.firstIndex(of: "|") {
            let iso = String(trimmed[..<separator])
            let digits = String(trimmed[trimmed.index(after: separator)...]).filter(\.isNumber)
            if let country = countries.first(where: { $0.iso == iso }) {
                return (country, nationalDigits(digits, country: country))
            }
        }
        let digits = trimmed.filter(\.isNumber)
        let international = trimmed.hasPrefix("+") || trimmed.hasPrefix("00")
        let body = trimmed.hasPrefix("00") ? String(digits.dropFirst(2)) : digits
        if international || body.count > 11, let match = matchDial(body) {
            return match
        }
        if isValidBrazil(digits) { return (.brazil, digits) }
        return (.brazil, nationalDigits(digits, country: .brazil))
    }

    private static func isValidBrazil(_ national: String) -> Bool {
        guard national.count == 10 || national.count == 11 else { return false }
        let area = String(national.prefix(2))
        guard brazilAreaCodes.contains(area) else { return false }
        let subscriber = national.dropFirst(2)
        guard let first = subscriber.first else { return false }
        if subscriber.count == 9 { return first == "9" }
        return ("2"..."5").contains(String(first))
    }

    private static func formatBrazil(_ digits: String) -> String {
        if digits.isEmpty { return "" }
        if digits.count == 1 { return "(\(digits)" }
        let area = digits.prefix(2)
        let rest = digits.dropFirst(2)
        if rest.isEmpty { return "(\(area)) " }
        let mobile = digits.count > 10
        let firstGroup = mobile ? 5 : 4
        if rest.count <= firstGroup { return "(\(area)) \(rest)" }
        let head = rest.prefix(firstGroup)
        let tail = rest.dropFirst(firstGroup)
        return "(\(area)) \(head)-\(tail)"
    }

    private static func formatGroups(_ digits: String) -> String {
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, index.isMultiple(of: 3) { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private static func matchDial(_ digits: String) -> (PhoneCountry, String)? {
        let preferred = Locale.current.region?.identifier
        let ordered = countries.sorted { lhs, rhs in
            if lhs.dial.count != rhs.dial.count { return lhs.dial.count > rhs.dial.count }
            let lhsPreferred = lhs.iso == preferred
            let rhsPreferred = rhs.iso == preferred
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.name < rhs.name
        }
        for country in ordered where digits.hasPrefix(country.dial) {
            let national = String(digits.dropFirst(country.dial.count))
            guard country.nationalRange.contains(national.count) else { continue }
            guard isValid(national: national, country: country) else { continue }
            return (country, national)
        }
        return nil
    }
}
