import Foundation

/// Facts about the North American Numbering Plan that decide which numbers are
/// worth handing to CallKit.
///
/// A NANP number is the country code `1`, then a 3-digit area code (NPA), a
/// 3-digit central office code (NXX), and a 4-digit line number:
///
///     +1 (415) 555-0134
///         NPA  NXX  line
///
/// CallKit identifies a number as an `Int64` holding exactly those digits, so
/// `+1 (415) 555-0134` is `14155550134`.
enum NANP {

    static let countryCode: Int64 = 1

    /// Digits after the country code: 3 for the area code, 3 for the exchange,
    /// 4 for the line number.
    static let nationalDigits = 10

    /// N11 codes — 211, 311, … 911 — are reserved service codes. They are never
    /// assigned as an area code or as a central office code, so skipping them
    /// removes 80,000 numbers per area code that can never ring.
    static let serviceCodes: Set<Int> = [211, 311, 411, 511, 611, 711, 811, 911]

    /// Central office codes run 200…999: the first digit of an NXX is never 0
    /// or 1, which is what keeps a full area code at 792 exchanges rather than
    /// 1,000.
    static let firstExchange = 200
    static let lastExchange = 999

    static func isAssignableExchange(_ nxx: Int) -> Bool {
        (firstExchange...lastExchange).contains(nxx) && !serviceCodes.contains(nxx)
    }

    /// Area codes follow the same shape as exchanges. This deliberately accepts
    /// codes that are merely *possible* rather than currently assigned, so a
    /// newly split area code works without an app update.
    static func isPlausibleAreaCode(_ npa: Int) -> Bool {
        (firstExchange...lastExchange).contains(npa) && !serviceCodes.contains(npa)
    }

    /// The `CXCallDirectoryPhoneNumber` value for a given NPA / NXX / line.
    static func phoneNumber(npa: Int, nxx: Int, line: Int) -> Int64 {
        countryCode * 10_000_000_000
            + Int64(npa) * 10_000_000
            + Int64(nxx) * 10_000
            + Int64(line)
    }
}
