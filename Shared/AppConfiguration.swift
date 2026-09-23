import Foundation

/// Identifiers that the app and the Call Directory extension have to agree on.
///
/// These three strings are duplicated in `project.yml` and in the two
/// `.entitlements` files. `scripts/configure.sh` rewrites all of them together —
/// prefer it over editing by hand, because a mismatch between any two of them
/// fails silently at runtime (the extension loads, finds no rules, and blocks
/// nothing).
enum AppConfiguration {

    /// Bundle identifier of the embedded Call Directory extension, or nil when
    /// the app carries no extension at all.
    ///
    /// Read from the bundle rather than hard-coded, because sideloading tools
    /// re-sign under your own team and rewrite bundle identifiers as they go.
    /// Nil is the case that matters: sideloaders offer a "remove app
    /// extensions" option to conserve App IDs against a free account's quota,
    /// and with it the app installs, opens and looks entirely normal while
    /// being incapable of blocking a single call. iOS reports that only as
    /// `noExtensionFound` on the next API call, so it is detected directly.
    ///
    /// Always nil inside the extension itself — an extension has no plug-ins to
    /// enumerate — so only the app should consult it.
    static let embeddedExtensionIdentifier: String? = {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: plugIns,
                  includingPropertiesForKeys: nil
              ),
              let appex = contents.first(where: { $0.pathExtension == "appex" })
        else { return nil }
        return Bundle(url: appex)?.bundleIdentifier
    }()

    /// Whether this copy of the app actually shipped with its extension.
    static var isExtensionEmbedded: Bool { embeddedExtensionIdentifier != nil }

    /// The identifier `CXCallDirectoryManager` is addressed with.
    ///
    /// Falls back to the conventional name when nothing is embedded, so calls
    /// still return a meaningful CallKit error instead of being skipped.
    static var callDirectoryExtensionIdentifier: String {
        embeddedExtensionIdentifier
            ?? (Bundle.main.bundleIdentifier ?? "com.example.spamblock") + ".CallDirectory"
    }

    /// App Group container both targets read and write the rule list through.
    static let appGroupIdentifier = "group.com.example.spamblock"
}
