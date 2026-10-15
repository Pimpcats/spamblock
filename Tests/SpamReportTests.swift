import Foundation
import XCTest

final class SpamReportTests: XCTestCase {

    private let number: Int64 = 19_095_550_134

    // MARK: - The report

    func testShowsTheNumberTheWayItIsDialled() {
        let report = SpamReport(number: number)
        XCTAssertEqual(report.nationalNumber, "9095550134")
        XCTAssertEqual(report.formatted, "(909) 555-0134")
    }

    func testReportsTakenBackAreNotBlocked() {
        let reports = [
            SpamReport(number: number),
            SpamReport(number: 12_135_550_199, issue: 7, isWithdrawn: true),
        ]
        XCTAssertEqual(SpamReport.blocked(reports), [number])
    }

    // MARK: - Storage

    func testReportsRoundTripThroughTheSharedContainer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RuleStore(directory: directory)
        XCTAssertEqual(store.loadSpamReports(), [])

        let reports = [
            SpamReport(number: number, reportedAt: Date(timeIntervalSince1970: 1_790_000_000), issue: 12),
            SpamReport(number: 12_135_550_199, reportedAt: Date(timeIntervalSince1970: 1_790_000_100), isWithdrawn: true),
        ]
        try store.saveSpamReports(reports)
        XCTAssertEqual(store.loadSpamReports(), reports)
    }

    func testWithoutAContainerReportsCanNotBeSaved() {
        let store = RuleStore(directory: nil)
        XCTAssertEqual(store.loadSpamReports(), [])
        XCTAssertThrowsError(try store.saveSpamReports([SpamReport(number: number)]))
    }

    // MARK: - Joining the published list

    func testReportsJoinThePublishedListInOrderWithoutDuplicates() {
        let published: [Int64] = [12_135_550_100, 14_155_550_100, 19_095_550_100]
        let reported: [Int64] = [19_995_550_100, 12_005_550_100, 14_155_550_100, 12_005_550_100]
        XCTAssertEqual(
            KnownSpamList.merging(published, with: reported),
            [12_005_550_100, 12_135_550_100, 14_155_550_100, 19_095_550_100, 19_995_550_100]
        )
    }

    func testEitherListCanBeEmpty() {
        let published: [Int64] = [12_135_550_100, 14_155_550_100]
        XCTAssertEqual(KnownSpamList.merging(published, with: []), published)
        XCTAssertEqual(KnownSpamList.merging([], with: [14_155_550_100]), [14_155_550_100])
    }

    // MARK: - Filing on GitHub

    func testAFiledReportIsAnIssueTheDataWorkflowRecognises() throws {
        let request = GitHubReports.fileRequest(for: SpamReport(number: number), token: "github_pat_example")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/Pimpcats/spamblock-data/issues")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github_pat_example")
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        // ftc_spamlist.py lists the open issues whose title starts this way,
        // and reads the number from the rest of the title.
        XCTAssertEqual(body["title"], "Spam report: (909) 555-0134")
    }

    func testTakingAReportBackClosesItsIssue() throws {
        let request = GitHubReports.closeRequest(issue: 42, token: "github_pat_example")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/Pimpcats/spamblock-data/issues/42")
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["state"], "closed")
    }

    func testFailuresSayWhatToFix() {
        XCTAssertNil(GitHubReports.failure(forStatus: 201))
        XCTAssertEqual(GitHubReports.failure(forStatus: 401), .tokenRejected)
        XCTAssertEqual(GitHubReports.failure(forStatus: 403), .noAccess)
        XCTAssertEqual(GitHubReports.failure(forStatus: 404), .noAccess)
        XCTAssertEqual(GitHubReports.failure(forStatus: 500), .unexpected(status: 500))
    }

    // MARK: - Reading a pasted number

    func testReadsNumbersAsTheyArePasted() {
        let pasted = [
            "(909) 555-0134",
            "+1 (909) 555-0134",
            "909.555.0134",
            "19095550134",
            // Copied from Recents, with the invisible direction marks iOS adds.
            "\u{202D}+1 (909) 555-0134\u{202C}",
        ]
        for text in pasted {
            XCTAssertEqual(ContactExemptions.phoneNumber(from: text), number, text)
        }
        XCTAssertNil(ContactExemptions.phoneNumber(from: "555-0134"))
    }
}
