import Foundation
import XCTest

final class KnownSpamListTests: XCTestCase {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Parsing

    func testParsesTheOneNumberPerLineFormat() throws {
        let numbers = try KnownSpamList.parse(data("2015550123\n9095551234\n"))
        XCTAssertEqual(numbers, [12_015_550_123, 19_095_551_234])
    }

    func testSortsAndDeduplicatesWhateverArrives() throws {
        // CallKit rejects a whole list over one number out of order or repeated.
        let numbers = try KnownSpamList.parse(data("9095551234\n2015550123\n9095551234\n"))
        XCTAssertEqual(numbers, [12_015_550_123, 19_095_551_234])
    }

    func testToleratesWindowsLineEndingsBlankLinesAndNoFinalNewline() throws {
        XCTAssertEqual(try KnownSpamList.parse(data("2015550123\r\n\r\n9095551234")),
                       [12_015_550_123, 19_095_551_234])
    }

    func testAnEmptyListIsValid() throws {
        XCTAssertEqual(try KnownSpamList.parse(Data()), [])
        XCTAssertEqual(try KnownSpamList.parse(data("\n")), [])
    }

    func testOneBadLineRejectsTheFile() {
        let cases: [(String, Int)] = [
            ("2015550123\n909555123\n", 2),      // nine digits: cut off
            ("2015550123\n90955512345\n", 2),    // eleven
            ("19095551234\n", 1),                // country code included
            ("909-555-1234\n", 1),               // formatted
            ("2015550123\n<html>\n", 2),         // an error page, not a list
            ("1095551234\n", 1),                 // area code can't start with 1
            ("9115551234\n", 1),                 // N11 area code
            ("9094111234\n", 1),                 // N11 exchange
            ("9091551234\n", 1),                 // exchange can't start with 1
        ]
        for (text, line) in cases {
            XCTAssertThrowsError(try KnownSpamList.parse(data(text)), text) { error in
                XCTAssertEqual(error as? KnownSpamList.ParseError, .malformedLine(line), text)
            }
        }
    }

    func testRefusesMoreThanTheLimit() {
        XCTAssertThrowsError(try KnownSpamList.parse(data("2015550123\n2015550124\n2015550125\n"), limit: 2)) { error in
            XCTAssertEqual(error as? KnownSpamList.ParseError, .tooManyNumbers(limit: 2))
        }
        XCTAssertEqual(try KnownSpamList.parse(data("2015550123\n2015550124\n"), limit: 2).count, 2)
    }

    // MARK: - Contacts

    func testSkipsContactsAndCountsThem() {
        let numbers: [Int64] = [12_015_550_123, 13_105_550_100, 19_095_551_234]
        let exempt: [Int64] = [12_015_550_000, 13_105_550_100, 19_999_999_999]
        var blocked: [Int64] = []
        let skipped = KnownSpamList.forEachEntry(in: numbers, exempt: exempt) { blocked.append($0) }
        XCTAssertEqual(blocked, [12_015_550_123, 19_095_551_234])
        XCTAssertEqual(skipped, 1)
    }

    // MARK: - Loading

    private func temporaryCache() -> KnownSpamList.Cache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return KnownSpamList.Cache(fileURL: directory.appendingPathComponent("KnownSpam/spam-numbers.txt"))
    }

    func testADownloadIsUsedAndSaved() async throws {
        let cache = temporaryCache()
        let loaded = try await KnownSpamList.load(download: { self.data("9095551234\n") }, cache: cache)
        XCTAssertEqual(loaded.numbers, [19_095_551_234])
        XCTAssertEqual(loaded.source, .downloaded)
        XCTAssertEqual(cache.load(), data("9095551234\n"))
    }

    func testOfflineFallsBackToTheSavedCopy() async throws {
        let cache = temporaryCache()
        try cache.save(data("9095551234\n"))
        let loaded = try await KnownSpamList.load(download: { throw URLError(.notConnectedToInternet) }, cache: cache)
        XCTAssertEqual(loaded.numbers, [19_095_551_234])
        XCTAssertEqual(loaded.source, .saved)
        XCTAssertNotNil(loaded.downloadError)
    }

    func testABrokenDownloadNeitherLoadsNorReplacesTheSavedCopy() async throws {
        let cache = temporaryCache()
        try cache.save(data("9095551234\n"))
        let loaded = try await KnownSpamList.load(download: { self.data("9095551234\n909555") }, cache: cache)
        XCTAssertEqual(loaded.source, .saved)
        XCTAssertEqual(cache.load(), data("9095551234\n"))
    }

    func testWithNeitherThereIsAnErrorWorthShowing() async {
        do {
            _ = try await KnownSpamList.load(download: { throw URLError(.notConnectedToInternet) }, cache: temporaryCache())
            XCTFail("expected an error")
        } catch {
            let error = error as NSError
            XCTAssertEqual(error.domain, KnownSpamList.errorDomain)
            XCTAssertTrue(error.localizedDescription.contains("internet connection"))
        }
    }

    // MARK: - Describing the list

    func testReadsTheInfoTheDataRepositoryPublishes() throws {
        // As published, generated_at without a zone; later versions add a Z.
        let json = """
        {"count": 374, "sha256": "ed41", "generated_at": "2026-09-24T23:52:30",
         "window_days": 90, "min_reports": 3, "days_covered": 5}
        """
        let info = try JSONDecoder().decode(KnownSpamList.Info.self, from: data(json))
        XCTAssertEqual(info.count, 374)
        XCTAssertEqual(info.minReports, 3)
        XCTAssertEqual(info.windowDays, 90)
        XCTAssertEqual(info.generatedAt, Date(timeIntervalSince1970: 1_790_293_950))
        XCTAssertEqual(KnownSpamList.Info.date(from: "2026-09-24T23:52:30Z"), info.generatedAt)
    }

    // MARK: - Telling the extensions apart

    func testRecognisesTheKnownSpamExtension() {
        XCTAssertTrue(KnownSpamList.isKnownSpamExtension(infoDictionary: ["SpamBlockRole": "known-spam"]))
        XCTAssertFalse(KnownSpamList.isKnownSpamExtension(infoDictionary: ["SpamBlockSliceNumber": "1"]))
        XCTAssertFalse(KnownSpamList.isKnownSpamExtension(infoDictionary: nil))
    }
}
