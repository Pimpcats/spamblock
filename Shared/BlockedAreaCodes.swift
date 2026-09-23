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
//  The list is split evenly across the app's extensions — four of them,
//  showing in Settings as "SpamBlock — 1 of 4" through "4 of 4" — because one
//  extension can only hold so much. Keep each part under about 2 million: a
//  whole area code (7.9 million) fills all four. The app shows the per-part
//  size, and README.md explains the limit.
// ─────────────────────────────────────────────────────────────────────────────

enum BlockedAreaCodes {
    static let prefixes: [String] = [
        "909",  // San Bernardino / Inland Empire, CA — 7,920,000 numbers
    ]
}
