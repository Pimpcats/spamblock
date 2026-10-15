import Foundation

/// A number reported as spam from this iPhone, after a call from it got
/// through.
///
/// Two things follow from a report. The Known spam extension blocks the number
/// on this phone straight away, alongside the published list — the app keeps
/// reports in the App Group, where the extension reads them. And when the app
/// has a GitHub token, it files the report on spamblock-data, which adds the
/// number to the published list so every install blocks it.
struct SpamReport: Codable, Equatable, Identifiable {

    /// CallKit's form, country code included: (909) 555-0134 is 19095550134.
    let number: Int64
    let reportedAt: Date
    /// The issue on spamblock-data that puts the number on the shared list,
    /// once filed.
    var issue: Int?
    /// Taken back, but its issue isn't closed yet. No longer blocked here;
    /// kept only until the shared list has been told.
    var isWithdrawn: Bool

    init(number: Int64, reportedAt: Date = Date(), issue: Int? = nil, isWithdrawn: Bool = false) {
        self.number = number
        self.reportedAt = reportedAt
        self.issue = issue
        self.isWithdrawn = isWithdrawn
    }

    var id: Int64 { number }

    /// The ten digits after +1.
    var nationalNumber: String {
        String(number - NANP.countryCode * 10_000_000_000)
    }

    /// "(909) 555-0134".
    var formatted: String {
        PrefixValidator.formatted(nationalNumber)
    }

    /// The numbers to block from `reports`: those not taken back.
    static func blocked(_ reports: [SpamReport]) -> [Int64] {
        reports.filter { !$0.isWithdrawn }.map(\.number)
    }
}
