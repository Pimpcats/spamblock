import Foundation

/// Identifiers that the app and the Call Directory extension have to agree on.
///
/// These three strings are duplicated in `project.yml` and in the two
/// `.entitlements` files. `scripts/configure.sh` rewrites all of them together —
/// prefer it over editing by hand, because a mismatch between any two of them
/// fails silently at runtime (the extension loads, finds no rules, and blocks
/// nothing).
enum AppConfiguration {

    /// Bundle identifier of the Call Directory app extension target.
    ///
    /// `CXCallDirectoryManager` addresses the extension by this string. If it
    /// does not match the extension's actual bundle identifier, every call
    /// returns `noExtensionFound`.
    static let callDirectoryExtensionIdentifier = "com.example.spamblock.CallDirectory"

    /// App Group container both targets read and write the rule list through.
    static let appGroupIdentifier = "group.com.example.spamblock"

    /// Block list compiled into the extension, used only when the App Group
    /// container isn't reachable.
    ///
    /// App Groups need a paid Apple Developer membership. On a free account the
    /// capability can't be provisioned, the app and the extension get no shared
    /// storage, and nothing typed into the app can reach the extension. Listing
    /// prefixes here — same format as a rule, national digits only — makes the
    /// extension work anyway, at the cost of needing a rebuild to change them:
    ///
    ///     static let builtInPrefixes = ["415", "628555"]
    ///
    /// Leave it empty if you have a paid membership; the app is then the only
    /// source of rules.
    static let builtInPrefixes: [String] = []
}
