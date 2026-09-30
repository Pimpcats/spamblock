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

    // MARK: - Contact exemptions

    private func numbers(_ prefixes: [String], exempt: [Int64] = []) -> [Int64] {
        var out: [Int64] = []
        NumberPlan(prefixes: prefixes).forEachNumber(exempt: exempt) { out.append($0) }
        return out
    }

    func testExemptNumbersAreOmitted() {
        let all = numbers(["909555"])
        let victim = all[4_242]
        let kept = numbers(["909555"], exempt: [victim])

        XCTAssertEqual(kept.count, all.count - 1)
        XCTAssertFalse(kept.contains(victim))
        XCTAssertTrue(zip(kept, kept.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// The forward index through `exempt` is the part most likely to be wrong
    /// at the edges, so the edges get their own cases.
    func testExemptionsAtTheBoundaries() {
        let all = numbers(["909555"])
        let first = all.first!
        let last = all.last!

        XCTAssertEqual(numbers(["909555"], exempt: [first]).first, first + 1)
        XCTAssertEqual(numbers(["909555"], exempt: [last]).last, last - 1)
        XCTAssertEqual(numbers(["909555"], exempt: [first, last]).count, all.count - 2)
        XCTAssertEqual(numbers(["909555"], exempt: all), [])
    }

    func testExemptionsOutsideThePlanChangeNothing() {
        let all = numbers(["909555"])
        XCTAssertEqual(numbers(["909555"], exempt: [10_000_000_000]).count, all.count)
        XCTAssertEqual(numbers(["909555"], exempt: [19_999_999_999]).count, all.count)
        XCTAssertEqual(numbers(["909555"], exempt: [10_000_000_000, 19_999_999_999]).count, all.count)
    }

    func testDuplicateExemptionsCountOnce() {
        let all = numbers(["909555"])
        let victim = all[7]
        XCTAssertEqual(numbers(["909555"], exempt: [victim, victim]).count, all.count - 1)
    }

    func testCoversOnlyWhatWouldBeBlocked() {
        let plan = NumberPlan(prefixes: ["909"])
        XCTAssertTrue(plan.covers(NANP.phoneNumber(npa: 909, nxx: 555, line: 134)))
        XCTAssertFalse(plan.covers(NANP.phoneNumber(npa: 213, nxx: 555, line: 134)))
        // An N11 exchange is never emitted, so it is never "covered" either.
        XCTAssertFalse(plan.covers(14_154_110_000))
    }

    func testExemptedCountIgnoresContactsElsewhere() {
        let plan = NumberPlan(prefixes: ["909"])
        let contacts = [
            NANP.phoneNumber(npa: 213, nxx: 555, line: 9999),
            NANP.phoneNumber(npa: 909, nxx: 555, line: 100),
            NANP.phoneNumber(npa: 909, nxx: 720, line: 4242),
        ].sorted()
        XCTAssertEqual(plan.exemptedCount(from: contacts), 2)
    }

    /// The case that matters: a whole area code with a few contacts spared.
    func testWholeAreaCodeMinusContacts() {
        let contacts = [
            NANP.phoneNumber(npa: 213, nxx: 555, line: 9999),
            NANP.phoneNumber(npa: 909, nxx: 555, line: 100),
            NANP.phoneNumber(npa: 909, nxx: 720, line: 4242),
        ].sorted()

        var count = 0
        var previous: Int64 = 0
        var ascending = true
        NumberPlan(prefixes: ["909"]).forEachNumber(exempt: contacts) { number in
            if number <= previous { ascending = false }
            if contacts.contains(number) { ascending = false }  // must never be emitted
            previous = number
            count += 1
        }

        XCTAssertTrue(ascending)
        XCTAssertEqual(count, 7_920_000 - 2)
    }

    // MARK: - Parsing contact numbers

    func testContactNumbersParseFromTypedFormats() {
        let expected = NANP.phoneNumber(npa: 909, nxx: 555, line: 134)
        for text in ["(909) 555-0134", "909-555-0134", "+1 909 555 0134", "1 (909) 555.0134", "9095550134"] {
            XCTAssertEqual(ContactExemptions.phoneNumber(from: text), expected, "failed on \(text)")
        }
    }

    func testContactNumbersRejectNonNANP() {
        XCTAssertNil(ContactExemptions.phoneNumber(from: "611"))              // short code
        XCTAssertNil(ContactExemptions.phoneNumber(from: "+44 20 7946 0958")) // not +1
        XCTAssertNil(ContactExemptions.phoneNumber(from: ""))
        XCTAssertNil(ContactExemptions.phoneNumber(from: "909-555-013"))      // too short
        XCTAssertNil(ContactExemptions.phoneNumber(from: "909-411-0134"))     // N11 exchange
    }

    // MARK: - Splitting across extensions

    private func size(_ prefixes: [String]) -> Int {
        NumberPlan(prefixes: prefixes).entryCount
    }

    func testWholeAreaCodeSplitsIntoFourEqualParts() {
        let parts = NumberPlan.slices(of: ["909"], count: 4)
        XCTAssertEqual(parts.map(size), [1_980_000, 1_980_000, 1_980_000, 1_980_000])
        // Part 1 is exchanges 200-399: exactly what one extension was shown to hold.
        XCTAssertEqual(parts[0].first, "90920")
        XCTAssertEqual(parts[0].last, "90939")
    }

    /// Twelve parts, the build's count, hold three whole area codes at the
    /// size one extension is known to accept — and not a number more.
    func testTwelvePartsHoldThreeAreaCodesExactly() {
        let three = ["213", "415", "909"]
        XCTAssertEqual(Set(NumberPlan.slices(of: three, count: 12).map(size)), [1_980_000])
        XCTAssertEqual(NumberPlan.largestPart(of: three, count: 12), EntryBudget.comfortable)
        XCTAssertGreaterThan(NumberPlan.largestPart(of: three + ["818"], count: 12), EntryBudget.comfortable)
        XCTAssertGreaterThan(NumberPlan.largestPart(of: three + ["818555"], count: 12), EntryBudget.comfortable)
        // One area code spread over all twelve: pieces come in 100,000s (90,000
        // where an N11 code is skipped), so an even 660,000 isn't possible.
        XCTAssertEqual(NumberPlan.largestPart(of: ["909"], count: 12), 690_000)
    }

    /// The largest part is what has to fit in one extension, so that is what
    /// the split minimises — here, better than cutting at the nearest boundary
    /// past each even share, which gives 1,680,000.
    func testSplitMinimisesTheLargestPart() {
        XCTAssertEqual(NumberPlan.slices(of: ["909"], count: 5).map(size).max(), 1_590_000)
        XCTAssertEqual(NumberPlan.slices(of: ["909"], count: 8).map(size).max(), 990_000)
    }

    func testPartsTogetherAreExactlyTheWholePlan() {
        var whole: [Int64] = []
        NumberPlan(prefixes: ["9092", "213555"]).forEachNumber { whole.append($0) }

        var joined: [Int64] = []
        for part in NumberPlan.slices(of: ["9092", "213555"], count: 3) {
            NumberPlan(prefixes: part).forEachNumber { joined.append($0) }
        }
        XCTAssertEqual(joined, whole)
    }

    func testEveryPartIsAValidPlanOnItsOwn() {
        for part in NumberPlan.slices(of: ["909", "213", "4155550134"], count: 6) {
            XCTAssertEqual(NumberPlan.reduce(prefixes: part), part)
        }
    }

    /// Each extension computes the split on its own and keeps one part, so every
    /// one of them has to arrive at the same split.
    func testSplitIgnoresOrderAndDuplicates() {
        XCTAssertEqual(
            NumberPlan.slices(of: ["909", "213"], count: 5),
            NumberPlan.slices(of: ["213", "909", "909", "9092"], count: 5)
        )
    }

    func testSplitAlwaysReturnsTheRequestedNumberOfParts() {
        XCTAssertEqual(NumberPlan.slices(of: ["909"], count: 0), [])
        XCTAssertEqual(NumberPlan.slices(of: [], count: 3), [[], [], []])
        // Fewer pieces than parts: the extras load nothing rather than crash.
        XCTAssertEqual(NumberPlan.slices(of: ["9095551234"], count: 4).map(\.count), [1, 0, 0, 0])
    }

    func testRefineCutsToExchangeGroups() {
        XCTAssertEqual(NumberPlan.refine("909").count, 80)
        XCTAssertEqual(NumberPlan.refine("909").first, "90920")
        XCTAssertEqual(NumberPlan.refine("909").last, "90999")
        XCTAssertEqual(NumberPlan.refine("90920"), ["90920"])
        XCTAssertEqual(NumberPlan.refine("9091"), [])  // no exchange starts with 1
    }

    // MARK: - Which part an extension carries

    func testSliceReadsFromInfoPlistStrings() {
        let slice = ExtensionSlice(infoDictionary: ["SpamBlockSliceNumber": "2", "SpamBlockSliceCount": "4"])
        XCTAssertEqual(slice, ExtensionSlice(number: 2, count: 4))
        XCTAssertEqual(slice?.index, 1)
    }

    func testSliceAcceptsPlistNumbers() {
        XCTAssertEqual(
            ExtensionSlice(infoDictionary: ["SpamBlockSliceNumber": 3, "SpamBlockSliceCount": 4]),
            ExtensionSlice(number: 3, count: 4)
        )
    }

    func testSliceRejectsWhatIsntAPosition() {
        XCTAssertNil(ExtensionSlice(infoDictionary: nil))
        XCTAssertNil(ExtensionSlice(infoDictionary: [:]))
        XCTAssertNil(ExtensionSlice(infoDictionary: ["SpamBlockSliceNumber": "0", "SpamBlockSliceCount": "4"]))
        XCTAssertNil(ExtensionSlice(infoDictionary: ["SpamBlockSliceNumber": "5", "SpamBlockSliceCount": "4"]))
        XCTAssertNil(ExtensionSlice(infoDictionary: ["SpamBlockSliceNumber": "1", "SpamBlockSliceCount": "0"]))
        // What a build setting that was never defined leaves behind.
        XCTAssertNil(ExtensionSlice(infoDictionary: [
            "SpamBlockSliceNumber": "$(SPAMBLOCK_SLICE_NUMBER)",
            "SpamBlockSliceCount": "4",
        ]))
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
