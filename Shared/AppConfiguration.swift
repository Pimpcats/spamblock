import Foundation

/// Identifiers that the app and the Call Directory extension have to agree on.
///
/// These three strings are duplicated in `project.yml` and in the two
/// `.entitlements` files. `scripts/configure.sh` rewrites all of them together —
/// prefer it over editing by hand, because a mismatch between any two of them
/// fails silently at runtime (the extension loads, finds no rules, and blocks
/// nothing).
enum AppConfiguration {

    /// Bundle identifier of the Call Directory app extension.
    ///
    /// `CXCallDirectoryManager` addresses the extension by this string, and
    /// returns `noExtensionFound` for anything else — so it is read out of the
    /// embedded extension rather than hard-coded. Sideloading tools re-sign the
    /// app under your own team and rewrite bundle identifiers as they go, which
    /// would leave a hard-coded constant pointing at nothing.
    ///
    /// Only meaningful in the app; inside the extension there are no plug-ins to
    /// enumerate and the fallback is returned. Resolved once — it reads the
    /// filesystem, and the answer can't change while the app is running.
    static let callDirectoryExtensionIdentifier: String = {
        if let plugIns = Bundle.main.builtInPlugInsURL,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: plugIns,
               includingPropertiesForKeys: nil
           ),
           let appex = contents.first(where: { $0.pathExtension == "appex" }),
           let identifier = Bundle(url: appex)?.bundleIdentifier {
            return identifier
        }
        return (Bundle.main.bundleIdentifier ?? "com.example.spamblock") + ".CallDirectory"
    }()

    /// App Group container both targets read and write the rule list through.
    static let appGroupIdentifier = "group.com.example.spamblock"
}
