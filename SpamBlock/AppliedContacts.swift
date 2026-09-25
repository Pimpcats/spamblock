import Foundation

/// Which version of the address book each kind of extension last loaded.
///
/// The extensions skip your contacts when they load, so someone added since
/// then is still blocked until the next load. The app compares these with the
/// address book as it is now and reloads whatever is out of date. Stored as
/// fingerprints (`ContactExemptions.fingerprint(of:)`), never as numbers.
enum AppliedContacts {

    private static let partsKey = "appliedContactsParts"
    private static let knownSpamKey = "appliedContactsKnownSpam"

    /// Contacts in a blocked area code, as the area-code parts last loaded them.
    static var parts: String? {
        get { UserDefaults.standard.string(forKey: partsKey) }
        set { UserDefaults.standard.set(newValue, forKey: partsKey) }
    }

    /// All contacts, as the Known spam extension last loaded them.
    static var knownSpam: String? {
        get { UserDefaults.standard.string(forKey: knownSpamKey) }
        set { UserDefaults.standard.set(newValue, forKey: knownSpamKey) }
    }
}
