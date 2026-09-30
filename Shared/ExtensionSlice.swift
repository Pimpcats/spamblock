import Foundation

/// Which part of the block list a Call Directory extension carries.
///
/// One extension can only hold so many numbers, so the app ships several
/// identical extensions and the list is split between them — the arrangement
/// Settings shows as "SpamBlock — 1 of 12", "2 of 12", and so on. Each extension
/// learns its position from its own Info.plist, where the build writes
/// `SpamBlockSliceNumber` and `SpamBlockSliceCount`. Those survive re-signing,
/// unlike bundle identifiers, which sideloading tools rewrite.
struct ExtensionSlice: Equatable {

    /// 1-based, matching what Settings shows.
    let number: Int
    let count: Int

    var index: Int { number - 1 }

    /// The entire list in a single extension.
    static let whole = ExtensionSlice(number: 1, count: 1)

    init(number: Int, count: Int) {
        self.number = number
        self.count = count
    }

    /// Reads the position from an Info.plist dictionary, or nil if the keys are
    /// missing or don't describe a valid position.
    init?(infoDictionary: [String: Any]?) {
        guard let info = infoDictionary,
              let number = Self.integer(info["SpamBlockSliceNumber"]),
              let count = Self.integer(info["SpamBlockSliceCount"]),
              count >= 1,
              (1...count).contains(number)
        else { return nil }
        self.init(number: number, count: count)
    }

    /// This process's own position. An extension built without the keys carries
    /// the whole list, which is what a single-extension build always did.
    static var current: ExtensionSlice {
        ExtensionSlice(infoDictionary: Bundle.main.infoDictionary) ?? .whole
    }

    /// Build-setting substitution always writes strings, but a number is
    /// accepted too, so a hand-edited plist can't silently fall back to
    /// `.whole` and try to load the entire list in one extension.
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
