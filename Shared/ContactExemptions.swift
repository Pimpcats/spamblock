import Contacts
import Foundation

/// The numbers in your address book, so blocking an area code doesn't take your
/// own contacts with it.
///
/// CallKit never asks the app about a specific incoming call — it takes a fixed
/// list of numbers ahead of time — so "block 909 unless I know them" can't be
/// decided when the phone rings. It has to be decided when the list is built,
/// by leaving contacts out of it.
///
/// The extension reads contacts itself rather than being handed them by the
/// app. That's forced: passing data from the app would need an App Group, and a
/// free Apple ID can't provision one. It works because an extension shares the
/// containing app's Contacts permission — but the app has to ask for it first,
/// since an extension launched by iOS in the background can't show a prompt.
enum ContactExemptions {

    /// Whether contacts can be read right now.
    ///
    /// The default arm covers `.authorized` and, on iOS 18 and later,
    /// `.limited` — a partial selection still gives real numbers to exempt.
    static var isReadable: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined, .denied, .restricted:
            return false
        default:
            return true
        }
    }

    /// Every phone number in the address book, ascending and deduplicated.
    ///
    /// Ascending because `NumberPlan.forEachNumber` walks this in step with the
    /// numbers it generates, which only works if both are sorted.
    ///
    /// Returns an empty list when contacts can't be read. That fails toward
    /// blocking rather than toward letting calls through, so the app reports
    /// the permission state prominently instead of leaving it to be inferred.
    static func sortedNumbers() -> [Int64] {
        guard isReadable else { return [] }

        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        var numbers: Set<Int64> = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for phoneNumber in contact.phoneNumbers {
                    if let value = self.phoneNumber(from: phoneNumber.value.stringValue) {
                        numbers.insert(value)
                    }
                }
            }
        } catch {
            return []
        }

        return numbers.sorted()
    }

    /// A short digest of an ascending number list, for telling whether the
    /// contacts an extension skipped when it last loaded are still the ones in
    /// the address book. Stable across launches, unlike Swift's `Hasher`,
    /// which is seeded afresh in every process. (FNV-1a over each number's
    /// bytes, plus the count.)
    static func fingerprint(of numbers: [Int64]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for number in numbers {
            var bytes = UInt64(bitPattern: number)
            for _ in 0..<8 {
                hash ^= bytes & 0xff
                hash = hash &* 0x0000_0100_0000_01b3
                bytes >>= 8
            }
        }
        return "\(String(hash, radix: 16))-\(numbers.count)"
    }

    /// Converts a contact's phone number into the `Int64` CallKit uses, or nil
    /// if it isn't a complete North American number.
    ///
    /// Contacts hold whatever was typed — `(909) 555-0134`, `+1 909-555-0134`,
    /// `909.555.0134` — plus international numbers and short codes that have no
    /// bearing on a NANP block list.
    static func phoneNumber(from text: String) -> Int64? {
        let digits = PrefixValidator.normalize(text)
        guard digits.count == NANP.nationalDigits else { return nil }

        let npa = Int(digits.prefix(3)) ?? 0
        let nxx = Int(digits.dropFirst(3).prefix(3)) ?? 0
        let line = Int(digits.suffix(4)) ?? 0
        guard NANP.isPlausibleAreaCode(npa), NANP.isAssignableExchange(nxx) else { return nil }

        return NANP.phoneNumber(npa: npa, nxx: nxx, line: line)
    }
}
