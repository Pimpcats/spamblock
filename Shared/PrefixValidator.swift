import Foundation

enum RuleValidationError: LocalizedError, Equatable {
    case empty
    case tooShort
    case tooLong
    case invalidAreaCode(String)
    case unreachableExchange(String)
    case duplicate

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter an area code."
        case .tooShort:
            return "Enter at least the three digits of an area code."
        case .tooLong:
            return "That is longer than a phone number."
        case .invalidAreaCode(let npa):
            return "\(npa) isn’t a valid area code. Area codes start with 2–9 and are never 211, 311, 411, 511, 611, 711, 811, or 911."
        case .unreachableExchange(let digits):
            return "No real phone number starts with \(digits). The three digits after the area code start with 2–9 and are never an N11 service code."
        case .duplicate:
            return "That’s already in your block list."
        }
    }
}

/// Turns what someone types into the canonical national-digits form, and
/// explains why it won't do when it won't.
enum PrefixValidator {

    /// Strips formatting and the country code.
    ///
    /// A NANP national number never begins with 1, so a leading 1 on anything
    /// long enough to be more than an area code can only be the country code —
    /// which makes `+1 (415) 555`, `1-415-555` and `415555` the same rule.
    static func normalize(_ raw: String) -> String {
        var digits = String(raw.filter { $0.isASCII && $0.isNumber })
        if digits.hasPrefix("1") && digits.count >= 4 {
            digits.removeFirst()
        }
        return digits
    }

    /// Validates raw input, returning the normalised prefix to store.
    ///
    /// - Parameter existingPrefixes: prefixes already in the list, so the same
    ///   rule isn't added twice.
    static func validate(
        _ raw: String,
        existingPrefixes: Set<String> = []
    ) -> Result<String, RuleValidationError> {
        let prefix = normalize(raw)

        guard !prefix.isEmpty else { return .failure(.empty) }
        guard prefix.count >= 3 else { return .failure(.tooShort) }
        guard prefix.count <= 10 else { return .failure(.tooLong) }

        let areaCode = String(prefix.prefix(3))
        guard let npa = Int(areaCode), NANP.isPlausibleAreaCode(npa) else {
            return .failure(.invalidAreaCode(areaCode))
        }
        guard !NumberPlan.candidateExchanges(for: prefix).isEmpty else {
            return .failure(.unreachableExchange(formatted(prefix)))
        }
        guard !existingPrefixes.contains(prefix) else { return .failure(.duplicate) }

        return .success(prefix)
    }

    /// Renders a prefix as a phone number with the unspecified digits masked,
    /// e.g. `415555` → `(415) 555-••••`.
    static func formatted(_ prefix: String) -> String {
        var digits = Array(prefix.prefix(10))
        while digits.count < 10 { digits.append("•") }
        let npa = String(digits[0..<3])
        let nxx = String(digits[3..<6])
        let line = String(digits[6..<10])
        return "(\(npa)) \(nxx)-\(line)"
    }

    /// Plain-language summary of a rule's reach, for the row subtitle.
    static func scopeDescription(_ prefix: String) -> String {
        switch prefix.count {
        case 3:
            return "Every number in area code \(prefix)"
        case 4, 5:
            return "Area code \(prefix.prefix(3)), exchanges starting \(prefix.dropFirst(3))"
        case 6:
            return "Area code \(prefix.prefix(3)), exchange \(prefix.dropFirst(3))"
        case 10:
            return "This one number"
        default:
            return "Area code \(prefix.prefix(3)), numbers starting \(prefix.dropFirst(3))"
        }
    }
}
