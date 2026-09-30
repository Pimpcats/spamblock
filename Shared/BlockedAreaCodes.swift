import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  The starting list. With an App Group — a paid Apple Developer account —
//  the app saves its own copy the first time it runs, and from then on the
//  list is edited in the app; see "Changing the list" in README.md.
//
//  Without one, this is the list: passing rules from the app to the call
//  blocking extensions needs an App Group. EDIT IT, then commit and push;
//  GitHub rebuilds the app and you reinstall it.
//
//  Each entry is the digits after +1, and blocks every number starting with
//  them:
//
//      "415"         the whole 415 area code        7,920,000 numbers
//      "415555"      just the (415) 555 exchange       10,000 numbers
//      "4155550134"  one specific number                    1 number
//
//  The list is split evenly across the app's extensions — twelve of them,
//  showing in Settings as "SpamBlock — 1 of 12" through "12 of 12" — because
//  one extension can only hold so much. Each part holds about 2 million, so
//  three whole area codes (7.9 million each) fill all twelve. The app shows
//  the per-part size, and README.md explains the limit.
// ─────────────────────────────────────────────────────────────────────────────

enum BlockedAreaCodes {
    static let prefixes: [String] = [
        "909",  // San Bernardino / Inland Empire, CA — 7,920,000 numbers
    ]
}
