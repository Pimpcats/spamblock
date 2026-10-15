import Foundation

/// The numbers reported from this iPhone: reporting one, taking a report back,
/// and filing them on the shared list when there's a GitHub token.
///
/// Every change is saved to the App Group first. That's what blocks the number
/// here, once the Known spam extension reloads, so it never waits on GitHub.
/// Filing follows when GitHub can be reached; until then a report waits, and
/// the app tries again each time it's opened.
@MainActor
final class SpamReportsController: ObservableObject {

    @Published private(set) var reports: [SpamReport]
    @Published private(set) var hasToken: Bool
    /// Why reports aren't reaching the shared list, when it's something the
    /// user has to fix. Not set for a missing connection, which fixes itself.
    @Published private(set) var problem: String?
    @Published private(set) var isFiling = false

    private let store = RuleStore.shared

    init() {
        reports = RuleStore.shared.loadSpamReports()
        hasToken = SharedListToken.load() != nil
    }

    /// Whether reports can block anything: they reach the Known spam
    /// extension through the App Group.
    var isAvailable: Bool { store.isAvailable }

    /// The reports in force, newest first.
    var current: [SpamReport] {
        reports.filter { !$0.isWithdrawn }.sorted { $0.reportedAt > $1.reportedAt }
    }

    func isReported(_ number: Int64) -> Bool {
        current.contains { $0.number == number }
    }

    func status(of report: SpamReport) -> String {
        if report.issue != nil { return "Sent to the shared list" }
        if !hasToken { return "On this iPhone only" }
        return isFiling ? "Sending to the shared list…" : "Waiting to send to the shared list"
    }

    /// Saves a report, and returns whether it was saved — if it wasn't, it
    /// can't be blocked either, and `problem` says why.
    @discardableResult
    func report(_ number: Int64) -> Bool {
        var updated = reports
        if let index = updated.firstIndex(where: { $0.number == number }) {
            // Taken back, then reported again before the shared list heard.
            updated[index].isWithdrawn = false
        } else {
            updated.append(SpamReport(number: number))
        }
        do {
            try store.saveSpamReports(updated)
        } catch {
            problem = "Couldn’t save the report: \(error.localizedDescription)"
            return false
        }
        reports = updated
        fileWhenPossible()
        return true
    }

    func withdraw(_ report: SpamReport) {
        guard let index = reports.firstIndex(where: { $0.number == report.number }) else { return }
        if reports[index].issue == nil {
            reports.remove(at: index)  // never reached the shared list
        } else {
            reports[index].isWithdrawn = true
        }
        save()
        fileWhenPossible()
    }

    // MARK: - The token

    func setToken(_ token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try SharedListToken.save(token)
        } catch {
            problem = "Couldn’t keep the token in the Keychain: \(error.localizedDescription)"
            return
        }
        hasToken = true
        problem = nil
        Task {
            do {
                try await GitHubReports(token: token).check()
                await file()
            } catch {
                problem = Self.describe(error)
            }
        }
    }

    func removeToken() {
        SharedListToken.delete()
        hasToken = false
        problem = nil
    }

    // MARK: - Filing

    func fileWhenPossible() {
        Task { await file() }
    }

    /// Files the reports that haven't been, and closes the issues of those
    /// taken back. Stops at the first failure; whatever is left is saved and
    /// retried next time.
    ///
    /// The list can change while a request is out, so each result is applied
    /// to the list as it is by then, not as it was when the request went.
    func file() async {
        guard !isFiling, let token = SharedListToken.load() else { return }
        isFiling = true
        defer { isFiling = false }
        let github = GitHubReports(token: token)
        do {
            for report in reports where report.issue == nil && !report.isWithdrawn {
                let issue = try await github.file(report)
                if let index = reports.firstIndex(where: { $0.number == report.number && !$0.isWithdrawn }) {
                    reports[index].issue = issue
                    save()
                } else {
                    try await github.close(issue: issue)  // taken back while it was being filed
                }
            }
            for report in reports where report.isWithdrawn {
                if let issue = report.issue {
                    try await github.close(issue: issue)
                }
                if let index = reports.firstIndex(where: { $0.number == report.number }) {
                    if reports[index].isWithdrawn {
                        reports.remove(at: index)
                    } else {
                        reports[index].issue = nil  // reported again meanwhile: file it afresh
                    }
                    save()
                }
            }
            problem = nil
        } catch is URLError {
            // Offline or GitHub unreachable: the reports wait, and say so.
        } catch {
            problem = Self.describe(error)
        }
    }

    private func save() {
        try? store.saveSpamReports(reports)
    }

    private static func describe(_ error: Error) -> String {
        if error is URLError {
            return "Couldn’t reach GitHub to check the token. Reports will be sent once it can be reached."
        }
        return error.localizedDescription
    }
}
