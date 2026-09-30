import Foundation
import XCTest

final class RuleStoreTests: XCTestCase {

    private func temporaryStore() throws -> RuleStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return RuleStore(directory: directory)
    }

    // MARK: - Saved rules

    func testNothingSavedIsDifferentFromSavedEmpty() throws {
        // Nil means the built-in list applies; empty means block nothing.
        let store = try temporaryStore()
        XCTAssertNil(store.loadSaved())
        try store.save([])
        XCTAssertEqual(store.loadSaved(), [])
    }

    func testRulesRoundTrip() throws {
        let store = try temporaryStore()
        let rules = [BlockRule(prefix: "909"), BlockRule(prefix: "213555", note: "gym", isEnabled: false)]
        try store.save(rules)
        XCTAssertEqual(store.loadSaved(), rules)
    }

    func testWithoutAContainerThereIsNothingToLoadAndSavingFails() {
        let store = RuleStore(directory: nil)
        XCTAssertFalse(store.isAvailable)
        XCTAssertNil(store.loadSaved())
        XCTAssertThrowsError(try store.save([BlockRule(prefix: "909")]))
    }

    // MARK: - Part reports

    func testPartReportsAreKeptPerPart() throws {
        let store = try temporaryStore()
        let first = RuleStore.PartReport(prefixes: ["909"], entries: 660_000, loadedAt: Date(timeIntervalSince1970: 1_790_000_000))
        try store.saveReport(first, part: 1)
        XCTAssertEqual(store.loadReport(part: 1), first)
        XCTAssertNil(store.loadReport(part: 2))
    }

    // MARK: - Finding the App Group

    func testSideloadersRenamedGroupsComeFirst() {
        let renamed = "group.com.example.spamblock.ABCDE12345"
        XCTAssertEqual(
            AppConfiguration.appGroupCandidates(appInfo: ["ALTAppGroups": [renamed]], ownInfo: nil),
            [renamed, AppConfiguration.appGroupIdentifier]
        )
    }

    func testAnExtensionAndTheAppAgreeOnTheOrder() {
        // An extension passes the app's Info.plist and its own; the app passes
        // its own twice. Either way the app's renamed group leads.
        let app = ["ALTAppGroups": ["group.app"]]
        let extensionOwn = ["ALTAppGroups": ["group.extension"]]
        let fromExtension = AppConfiguration.appGroupCandidates(appInfo: app, ownInfo: extensionOwn)
        let fromApp = AppConfiguration.appGroupCandidates(appInfo: app, ownInfo: app)
        XCTAssertEqual(fromExtension.first, "group.app")
        XCTAssertEqual(fromApp, ["group.app", AppConfiguration.appGroupIdentifier])
    }

    func testSignedAsBuiltOnlyTheBuiltInGroupIsTried() {
        XCTAssertEqual(
            AppConfiguration.appGroupCandidates(appInfo: [:], ownInfo: nil),
            [AppConfiguration.appGroupIdentifier]
        )
    }
}
