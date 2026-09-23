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

    /// Every Call Directory extension inside the app, in part order.
    ///
    /// Read from the bundle rather than hard-coded, because sideloading tools
    /// re-sign under your own team and rewrite bundle identifiers as they go.
    /// Empty is the case that matters most: sideloaders offer to remove app
    /// extensions to conserve App IDs, and with that the app installs, opens
    /// and looks entirely normal while being unable to block a single call.
    ///
    /// Only meaningful in the app — an extension has no plug-ins of its own.
    static let embeddedExtensions: [EmbeddedExtension] = {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: plugIns,
                  includingPropertiesForKeys: nil
              )
        else { return [] }

        return contents
            .filter { $0.pathExtension == "appex" }
            .compactMap { url -> EmbeddedExtension? in
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier
                else { return nil }
                let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
                guard point == "com.apple.callkit.call-directory" else { return nil }
                return EmbeddedExtension(
                    bundleIdentifier: identifier,
                    slice: ExtensionSlice(infoDictionary: bundle.infoDictionary) ?? .whole
                )
            }
            .sorted { $0.slice.number < $1.slice.number }
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
}
