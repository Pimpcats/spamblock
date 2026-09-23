import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  EDIT THIS LIST, then commit and push. GitHub rebuilds the app and you
//  reinstall it — see "Changing the list" in README.md.
//
//  This is how the app works on a free Apple ID. Passing rules from the app to
//  the call blocking extension needs an App Group, and App Groups require a
//  paid Apple Developer membership. Compiled in, the list needs no App Group
//  and no membership — the trade is that changing it means a rebuild.
//
//  Each entry is the digits after +1, and blocks every number starting with
//  them:
//
//      "415"         the whole 415 area code        7,920,000 numbers
//      "415555"      just the (415) 555 exchange       10,000 numbers
//      "4155550134"  one specific number                    1 number
//
//  Keep the total under about 8 million — roughly one full area code. The app
//  shows the running total, and README.md explains the ceiling.
// ─────────────────────────────────────────────────────────────────────────────

enum BlockedAreaCodes {
    static let prefixes: [String] = [
        // Diagnostic. The full "909" (7,920,000) and its lower half
        // (3,960,000) were both rejected with "the data provided was
        // invalid", even once the extension was signed with its own App ID.
        // 100,000 is far below any plausible per-extension ceiling, so this
        // separates the two remaining explanations: if it loads, the list was
        // too large; if it fails, there is a bug that doesn't depend on size.
        "90920",  // (909) 200-0000 through (909) 209-9999
    ]
}
