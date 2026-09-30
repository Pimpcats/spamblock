import Foundation

/// Identifiers that the app and the Call Directory extension have to agree on.
///
/// These three strings are duplicated in `project.yml` and in the two
/// `.entitlements` files. `scripts/configure.sh` rewrites all of them together —
/// prefer it over editing by hand, because a mismatch between any two of them
/// fails silently at runtime (the extension loads, finds no rules, and blocks
/// nothing).
enum AppConfiguration {

    /// A Call Directory extension found inside the app.
    struct EmbeddedExtension: Equatable {
        let bundleIdentifier: String
        let slice: ExtensionSlice
    }

    /// Every Call Directory extension inside the app that carries a part of
    /// the area-code list, in part order.
    ///
    /// Read from the bundle rather than hard-coded, because sideloading tools
    /// re-sign under your own team and rewrite bundle identifiers as they go.
    /// Empty is the case that matters most: sideloaders offer to remove app
    /// extensions to conserve App IDs, and with that the app installs, opens
    /// and looks entirely normal while being unable to block a single call.
    ///
    /// Only meaningful in the app — an extension has no plug-ins of its own.
    static let embeddedExtensions: [EmbeddedExtension] = callDirectoryBundles
        .filter { !KnownSpamList.isKnownSpamExtension(infoDictionary: $0.infoDictionary) }
        .compactMap { bundle -> EmbeddedExtension? in
            guard let identifier = bundle.bundleIdentifier else { return nil }
            return EmbeddedExtension(
                bundleIdentifier: identifier,
                slice: ExtensionSlice(infoDictionary: bundle.infoDictionary) ?? .whole
            )
        }
        .sorted { $0.slice.number < $1.slice.number }

    /// The extension that blocks the known-spam list, or nil if this install
    /// doesn't have it — a sideloader can drop it like any other.
    static let knownSpamExtensionIdentifier: String? = callDirectoryBundles
        .first(where: { KnownSpamList.isKnownSpamExtension(infoDictionary: $0.infoDictionary) })?.bundleIdentifier

    /// Every Call Directory extension inside the app, of either kind.
    private static let callDirectoryBundles: [Bundle] = {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: plugIns,
                  includingPropertiesForKeys: nil
              )
        else { return [] }

        return contents
            .filter { $0.pathExtension == "appex" }
            .compactMap { Bundle(url: $0) }
            .filter { bundle in
                let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
                return point == "com.apple.callkit.call-directory"
            }
    }()

    static var isExtensionEmbedded: Bool { !embeddedExtensions.isEmpty }

    /// Parts the build shipped with that this install is missing.
    ///
    /// A sideloader's "choose app extensions" can keep some and drop others,
    /// which leaves those parts of the list unblocked with nothing to show
    /// for it in the app. Every part records how many there were meant to be,
    /// so any survivor can tell.
    static var missingPartNumbers: [Int] {
        guard let expected = embeddedExtensions.first?.slice.count else { return [] }
        let present = Set(embeddedExtensions.map(\.slice.number))
        return (1...expected).filter { !present.contains($0) }
    }

    /// App Group container both targets read and write the rule list through.
    static let appGroupIdentifier = "group.com.example.spamblock"

    /// The App Group this install can actually open, or nil if none.
    ///
    /// Signed as built, that's `appGroupIdentifier`. Sideloaders sign under
    /// your own team and rename app groups to keep them unique, recording the
    /// new names under `ALTAppGroups` in the app's Info.plist — SideStore and
    /// AltStore both do — so those are tried first. An extension reads the
    /// containing app's Info.plist, two folders up from its own bundle, so the
    /// app and every extension settle on the same group.
    static let resolvedAppGroupIdentifier: String? = appGroupCandidates(
        appInfo: containingAppBundle?.infoDictionary ?? Bundle.main.infoDictionary,
        ownInfo: Bundle.main.infoDictionary
    ).first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }

    /// Groups to try, in order: the sideloader's renamed ones as the app
    /// records them, then any in this bundle's own Info.plist, then the one
    /// built in. Each name once.
    static func appGroupCandidates(appInfo: [String: Any]?, ownInfo: [String: Any]?) -> [String] {
        let renamed = [appInfo, ownInfo].flatMap { ($0?["ALTAppGroups"] as? [String]) ?? [] }
        var seen = Set<String>()
        return (renamed + [appGroupIdentifier]).filter { seen.insert($0).inserted }
    }

    /// From inside an extension, the app that contains it; nil in the app.
    private static var containingAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }
}
