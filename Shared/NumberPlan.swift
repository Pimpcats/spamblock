import Foundation

/// Expands a set of `BlockRule`s into the phone numbers CallKit is given.
///
/// CallKit imposes two hard requirements on a call directory: entries must be
/// added in strictly ascending numerical order, and no number may repeat. It
/// rejects the whole directory otherwise — `entriesOutOfOrder` or
/// `duplicateEntries` — without naming the offending entry, and by then the
/// user is simply left with nothing blocked. So both properties are established
/// here, structurally, rather than hoped for at insertion time:
///
/// 1. `reduce(prefixes:)` drops any prefix already covered by a shorter one, so
///    what survives is pairwise non-overlapping and the expansions are disjoint.
/// 2. For prefixes where neither is a prefix of the other, lexicographic order
///    on the digit strings agrees with numeric order on everything they expand
///    to — they first differ at some digit position, and that digit decides both
///    comparisons. Sorting the prefixes therefore sorts the output.
/// 3. Within one prefix the loops run exchanges ascending, then line numbers
///    ascending, and the encoding is monotonic in that pair.
struct NumberPlan {

    /// Normalised prefixes: deduplicated, non-overlapping, ascending.
    let prefixes: [String]

    init(rules: [BlockRule]) {
        self.init(prefixes: rules.filter(\.isEnabled).map(\.prefix))
    }

    init(prefixes: [String]) {
        self.prefixes = NumberPlan.reduce(prefixes: prefixes)
    }

    // MARK: - Normalisation

    /// Collapses a raw prefix list into a disjoint, ascending one.
    ///
    /// Shortest first, because a prefix can only ever be covered by a strictly
    /// shorter one — so by the time a candidate is examined, every prefix that
    /// could absorb it has already been kept or discarded.
    static func reduce(prefixes: [String]) -> [String] {
        let usable = Set(prefixes).filter { isExpandable($0) }
        let byLength = usable.sorted { ($0.count, $0) < ($1.count, $1) }
        var kept: [String] = []
        for candidate in byLength where !kept.contains(where: { candidate.hasPrefix($0) }) {
            kept.append(candidate)
        }
        return kept.sorted()
    }

    /// Whether a prefix is well formed enough to expand.
    ///
    /// The extension re-reads rules from a file on disk that it does not
    /// control, so this is checked there and not only at data-entry time: a
    /// malformed prefix must be skipped, never trip a bounds check. A crashed
    /// extension blocks nothing at all.
    static func isExpandable(_ prefix: String) -> Bool {
        (3...10).contains(prefix.count) && prefix.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Expansion

    /// Exchanges (NXX) that are assignable *and* match whatever part of the
    /// exchange the prefix pins down.
    ///
    /// An empty result means the prefix can never match a real number — for
    /// example `4151`, since no exchange starts with 1.
    static func candidateExchanges(for prefix: String) -> [Int] {
        guard isExpandable(prefix) else { return [] }
        let digits = Array(prefix)
        let known = String(digits[3..<min(digits.count, 6)])
        return (NANP.firstExchange...NANP.lastExchange).filter { nxx in
            NANP.isAssignableExchange(nxx) && String(nxx).hasPrefix(known)
        }
    }

    /// The inclusive span of line numbers a prefix leaves open: all 10,000 when
    /// the prefix stops at or before the exchange, otherwise the block the
    /// remaining digits pin down (`4155550` → 0000…0999).
    static func lineRange(for prefix: String) -> ClosedRange<Int> {
        guard isExpandable(prefix) else { return 0...9999 }
        guard prefix.count > 6, let known = Int(prefix.dropFirst(6)) else { return 0...9999 }
        let scale = powersOfTen[10 - prefix.count]
        let base = known * scale
        return base...(base + scale - 1)
    }

    private static let powersOfTen = [1, 10, 100, 1_000, 10_000]

    /// How many numbers a single prefix expands to.
    static func entryCount(for prefix: String) -> Int {
        let lines = lineRange(for: prefix)
        return candidateExchanges(for: prefix).count * lines.count
    }

    /// Total entries this plan will hand to CallKit.
    var entryCount: Int {
        prefixes.reduce(0) { $0 + NumberPlan.entryCount(for: $1) }
    }

    /// Calls `body` once per blocked number, in strictly ascending order,
    /// leaving out anything in `exempt`.
    ///
    /// Nothing is accumulated: for a whole area code this yields 7.9 million
    /// numbers, and materialising them as an array would cost ~63 MB and get the
    /// extension killed.
    ///
    /// - Parameter exempt: numbers to leave unblocked — in practice the address
    ///   book, so blocking an area code doesn't take known callers with it.
    ///   **Must be sorted ascending.** Both sequences ascend, so one forward
    ///   index through `exempt` is enough; no per-number lookup, no hashing of
    ///   eight million values.
    func forEachNumber(exempt: [Int64] = [], _ body: (Int64) -> Void) {
        var exemptIndex = 0

        for prefix in prefixes {
            guard let npa = Int(prefix.prefix(3)) else { continue }
            let lines = NumberPlan.lineRange(for: prefix)
            for nxx in NumberPlan.candidateExchanges(for: prefix) {
                let base = NANP.phoneNumber(npa: npa, nxx: nxx, line: 0)
                for line in lines {
                    let number = base + Int64(line)
                    while exemptIndex < exempt.count && exempt[exemptIndex] < number {
                        exemptIndex += 1
                    }
                    if exemptIndex < exempt.count && exempt[exemptIndex] == number {
                        continue
                    }
                    body(number)
                }
            }
        }
    }

    /// Whether this plan would block `number` were it not exempt.
    ///
    /// Used to report how many contacts an area code would have caught, so the
    /// exemption is visible rather than something to take on trust.
    func covers(_ number: Int64) -> Bool {
        let digits = String(number)
        guard digits.count == NANP.nationalDigits + 1, digits.hasPrefix("1") else { return false }
        let national = String(digits.dropFirst())

        guard let nxx = Int(national.dropFirst(3).prefix(3)), NANP.isAssignableExchange(nxx) else {
            return false
        }
        return prefixes.contains { national.hasPrefix($0) }
    }

    /// How many of `exempt` this plan would otherwise have blocked.
    func exemptedCount(from exempt: [Int64]) -> Int {
        exempt.reduce(0) { $0 + (covers($1) ? 1 : 0) }
    }
}

/// Rough ceilings for how much iOS will swallow.
///
/// Apple documents no hard limit; what actually happens is that the extension
/// is killed if it exceeds its memory or time budget while loading, surfacing
/// as `maximumEntriesExceeded` or `loadingInterrupted`. These thresholds are
/// judgement calls, sized so that one full area code — 7.92 million numbers —
/// sits inside the comfortable band.
enum EntryBudget {
    static let comfortable = 8_000_000
    static let risky = 16_000_000

    enum Level {
        case comfortable, risky, overBudget
    }

    static func level(for entryCount: Int) -> Level {
        if entryCount <= comfortable { return .comfortable }
        if entryCount <= risky { return .risky }
        return .overBudget
    }
}
