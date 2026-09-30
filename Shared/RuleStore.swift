import Foundation

enum RuleStoreError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Can’t reach the shared App Group “\(AppConfiguration.appGroupIdentifier)”. Both the app and the Call Directory extension need the App Groups capability with exactly this identifier."
        }
    }
}

/// The rule list, stored in the App Group container shared by the app and the
/// extensions, along with what each part last loaded.
///
/// A file rather than shared `UserDefaults`: the extension is launched by the
/// system as a separate short-lived process, and reading a file gives a clear
/// answer about whether the data arrived. Writes are atomic, so an extension
/// that happens to be loading never sees a half-written list.
struct RuleStore {
    static let shared = RuleStore(
        directory: AppConfiguration.resolvedAppGroupIdentifier.flatMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    )

    private static let fileName = "block-rules.json"

    /// The shared container, or nil if this install has none. Injectable so
    /// tests can use a temporary folder.
    let directory: URL?

    var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    /// Whether the shared container exists at all.
    ///
    /// `false` means the App Group isn't provisioned — a free Apple ID can't
    /// create one, and a sideloader may not pass one on. Worth distinguishing
    /// from "no rules yet", because the two need completely different advice.
    var isAvailable: Bool { directory != nil }

    /// The rules as last saved, or nil if none have ever been saved here.
    ///
    /// Nil and empty mean different things. Nil is a container nobody has
    /// written to yet, where the built-in list should apply — a sideloader can
    /// leave an App Group in place that the app has never used. Empty is a
    /// list someone cleared on purpose, which blocks nothing.
    func loadSaved() -> [BlockRule]? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([BlockRule].self, from: data)
    }

    func save(_ rules: [BlockRule]) throws {
        guard let fileURL else { throw RuleStoreError.appGroupUnavailable }
        let data = try JSONEncoder().encode(rules)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - What each part loaded

    /// Written by each area-code part when it loads, so the app can confirm
    /// that every part read the list it saved. A part that reads a different
    /// container — a sideloader can hand the app and its extensions different
    /// App Groups — leaves no report where the app looks.
    struct PartReport: Codable, Equatable {
        /// The whole list the part split, not just its own share.
        let prefixes: [String]
        /// How many numbers this part handed to iOS.
        let entries: Int
        let loadedAt: Date
    }

    private func reportURL(part: Int) -> URL? {
        directory?.appendingPathComponent("part-\(part)-report.json")
    }

    func saveReport(_ report: PartReport, part: Int) throws {
        guard let url = reportURL(part: part) else { throw RuleStoreError.appGroupUnavailable }
        try JSONEncoder().encode(report).write(to: url, options: .atomic)
    }

    func loadReport(part: Int) -> PartReport? {
        guard let url = reportURL(part: part), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PartReport.self, from: data)
    }
}
