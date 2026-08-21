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
/// extension.
///
/// A file rather than shared `UserDefaults`: the extension is launched by the
/// system as a separate short-lived process, and reading a file gives a clear
/// answer about whether the data arrived. Writes are atomic, so an extension
/// that happens to be loading never sees a half-written list.
struct RuleStore {
    static let shared = RuleStore()

    private static let fileName = "block-rules.json"

    var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier)?
            .appendingPathComponent(Self.fileName)
    }

    /// Whether the shared container exists at all.
    ///
    /// `false` means the App Group isn't provisioned — the usual cause being a
    /// free Apple Developer account, which can't create one. Worth
    /// distinguishing from "no rules yet", because the two need completely
    /// different advice.
    var isAvailable: Bool { fileURL != nil }

    /// Returns an empty list rather than throwing: in the extension there is no
    /// one to show an error to, and blocking nothing is the safe failure.
    func load() -> [BlockRule] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([BlockRule].self, from: data)) ?? []
    }

    func save(_ rules: [BlockRule]) throws {
        guard let fileURL else { throw RuleStoreError.appGroupUnavailable }
        let data = try JSONEncoder().encode(rules)
        try data.write(to: fileURL, options: .atomic)
    }
}
