import Foundation

/// One entry in the block list: every number whose national digits begin with
/// `prefix` is blocked.
///
/// The prefix length is how you trade coverage against size, which matters
/// because iOS has to hold the expanded list in memory:
///
/// | Prefix        | Meaning                  | Numbers blocked |
/// | ------------- | ------------------------ | --------------- |
/// | `415`         | the whole area code      | 7,920,000       |
/// | `4155`        | exchanges 500–599        | 990,000         |
/// | `415555`      | one exchange             | 10,000          |
/// | `4155550134`  | one number               | 1               |
struct BlockRule: Codable, Identifiable, Hashable {
    var id: UUID
    /// National digits only: no country code, no formatting. 3…10 characters.
    var prefix: String
    /// Free-text reminder of why this rule exists. Not used for matching.
    var note: String
    var isEnabled: Bool

    init(id: UUID = UUID(), prefix: String, note: String = "", isEnabled: Bool = true) {
        self.id = id
        self.prefix = prefix
        self.note = note
        self.isEnabled = isEnabled
    }
}
