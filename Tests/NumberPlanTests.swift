import Foundation
import XCTest

/// Deterministic generator so a failure can be reproduced exactly.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class NumberPlanTests: XCTestCase {

    // MARK: - Sizes

    func testWholeAreaCodeCoversAssignableExchangesOnly() {
        // 200…999 is 800 codes, less the eight N11 service codes.
        XCTAssertEqual(NumberPlan.candidateExchanges(for: "415").count, 792)
        XCTAssertEqual(NumberPlan.entryCount(for: "415"), 7_920_000)
    }

    func testEntryCountByPrefixLength() {
        XCTAssertEqual(NumberPlan.entryCount(for: "4154"), 990_000)   // exchanges 400–499 less 411
        XCTAssertEqual(NumberPlan.entryCount(for: "41541"), 90_000)   // 410–419 less 411
        XCTAssertEqual(NumberPlan.entryCount(for: "415555"), 10_000)
        XCTAssertEqual(NumberPlan.entryCount(for: "4155550"), 1_000)
        XCTAssertEqual(NumberPlan.entryCount(for: "415555013"), 10)
        XCTAssertEqual(NumberPlan.entryCount(for: "4155550134"), 1)
    }

    func testPrefixesThatNoRealNumberCanMatch() {
        XCTAssertTrue(NumberPlan.candidateExchanges(for: "4151").isEmpty)  // exchange can't start with 1
        XCTAssertTrue(NumberPlan.candidateExchanges(for: "4150").isEmpty)  // …or 0
        XCTAssertTrue(NumberPlan.candidateExchanges(for: "415411").isEmpty) // N11 service code
    }

    // MARK: - Encoding

    func testPhoneNumberEncoding() {
        XCTAssertEqual(NANP.phoneNumber(npa: 415, nxx: 555, line: 134), 14_155_550_134)
    }

    // MARK: - Normalising the rule set

    func testBroaderRuleAbsorbsNarrowerOne() {
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["415", "415555"]), ["415"])
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["4155550134", "415555", "415"]), ["415"])
    }

    func testDuplicatesCollapseAndSiblingsSurvive() {
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["415", "415"]), ["415"])
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["415556", "415555"]), ["415555", "415556"])
    }

    func testResultIsSorted() {
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["718", "212", "415"]), ["212", "415", "718"])
    }

    func testMalformedPrefixesAreDropped() {
        // The extension re-reads this list from disk, so junk must be skipped
        // rather than crash a process that would otherwise block calls.
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["41", "41555501345", "abc", "41x", "", "415"]), ["415"])
        XCTAssertEqual(NumberPlan(prefixes: ["41"]).entryCount, 0)
    }

    func testDisabledRulesAreExcluded() {
        let rules = [
            BlockRule(prefix: "415", isEnabled: true),
            BlockRule(prefix: "212", isEnabled: false),
        ]
        XCTAssertEqual(NumberPlan(rules: rules).prefixes, ["415"])
    }

    // MARK: - The two properties CallKit enforces

    func testRandomRuleSetsAreStrictlyAscendingAndUnique() {
        for seed in 0..<200 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let prefixes = (0..<Int.random(in: 1...5, using: &rng)).map { _ in
                randomPrefix(minLength: 7, maxLength: 10, using: &rng)
            }

            let plan = NumberPlan(prefixes: prefixes)
            var numbers: [Int64] = []
            plan.forEachNumber { numbers.append($0) }

            XCTAssertTrue(
                zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 },
                "seed \(seed): not strictly ascending for \(prefixes)"
            )
            XCTAssertEqual(
                numbers.count, Set(numbers).count,
                "seed \(seed): duplicates for \(prefixes)"
            )
            XCTAssertEqual(
                numbers.count, plan.entryCount,
                "seed \(seed): entryCount disagrees with what was emitted for \(prefixes)"
            )
        }
    }

    func testMixedPrefixLengthsInterleaveCorrectly() {
        var numbers: [Int64] = []
        NumberPlan(prefixes: ["7185551234", "212555", "2125"]).forEachNumber { numbers.append($0) }
        XCTAssertEqual(NumberPlan.reduce(prefixes: ["7185551234", "212555", "2125"]), ["2125", "7185551234"])
        XCTAssertTrue(zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// The real workload: one whole area code, checked without ever holding the
    /// numbers in memory — which is also how the extension has to emit them.
    func testWholeAreaCodeStreamsInOrder() {
        var first: Int64?
        var previous: Int64 = 0
        var count = 0
        var ascending = true

        NumberPlan(prefixes: ["415"]).forEachNumber { number in
            if first == nil { first = number }
            if number <= previous { ascending = false }
            previous = number
            count += 1
        }

        XCTAssertTrue(ascending)
        XCTAssertEqual(count, 7_920_000)
        XCTAssertEqual(first, 14_152_000_000)   // +1 (415) 200-0000
        XCTAssertEqual(previous, 14_159_999_999) // +1 (415) 999-9999
    }

    // MARK: - Input handling

    func testNormalisationStripsFormattingAndCountryCode() {
        XCTAssertEqual(PrefixValidator.normalize("(415) 555-0134"), "4155550134")
        XCTAssertEqual(PrefixValidator.normalize("+1 415 555"), "415555")
        XCTAssertEqual(PrefixValidator.normalize("1-415-555-0134"), "4155550134")
        XCTAssertEqual(PrefixValidator.normalize("1415"), "415")
        XCTAssertEqual(PrefixValidator.normalize("415"), "415")
    }

    func testValidationRejectsWhatCannotRing() {
        XCTAssertEqual(validationError(for: ""), .empty)
        XCTAssertEqual(validationError(for: "41"), .tooShort)
        XCTAssertEqual(validationError(for: "41555501345"), .tooLong)
        XCTAssertEqual(validationError(for: "911"), .invalidAreaCode("911"))
        XCTAssertEqual(validationError(for: "199"), .invalidAreaCode("199"))
        XCTAssertNotNil(validationError(for: "415411"))
    }

    func testValidationAcceptsAndNormalises() {
        guard case .success(let prefix) = PrefixValidator.validate("(415) 555") else {
            return XCTFail("expected (415) 555 to validate")
        }
        XCTAssertEqual(prefix, "415555")
    }

    func testValidationRejectsDuplicates() {
        XCTAssertEqual(validationError(for: "415", existing: ["415"]), .duplicate)
    }

    func testFormattingMasksUnknownDigits() {
        XCTAssertEqual(PrefixValidator.formatted("415"), "(415) •••-••••")
        XCTAssertEqual(PrefixValidator.formatted("415555"), "(415) 555-••••")
        XCTAssertEqual(PrefixValidator.formatted("4155550134"), "(415) 555-0134")
    }

    // MARK: - Helpers

    private func validationError(for raw: String, existing: Set<String> = []) -> RuleValidationError? {
        if case .failure(let error) = PrefixValidator.validate(raw, existingPrefixes: existing) {
            return error
        }
        return nil
    }

    private func randomPrefix(
        minLength: Int,
        maxLength: Int,
        using rng: inout SeededGenerator
    ) -> String {
        let npa = (200...999).filter(NANP.isPlausibleAreaCode).randomElement(using: &rng)!
        let nxx = (200...999).filter(NANP.isAssignableExchange).randomElement(using: &rng)!
        let line = String(format: "%04d", Int.random(in: 0...9999, using: &rng))
        return String("\(npa)\(nxx)\(line)".prefix(Int.random(in: minLength...maxLength, using: &rng)))
    }
}
