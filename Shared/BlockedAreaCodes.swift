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
        // iOS rejected the full "909" (7,920,000 numbers) with "the data
        // provided was invalid" when the extension was switched on, so this is
        // the lower half of the area code — exchanges 200 through 599 — at
        // 3,960,000. Restore "909" once the ceiling is known.
        "9092",  // (909) 2xx-xxxx
        "9093",  // (909) 3xx-xxxx
        "9094",  // (909) 4xx-xxxx
        "9095",  // (909) 5xx-xxxx
    ]
}
