import XCTest

final class ContactFingerprintTests: XCTestCase {

    private let contacts: [Int64] = [12_015_550_123, 19_095_551_234]

    func testTheSameContactsGiveTheSameFingerprint() {
        XCTAssertEqual(ContactExemptions.fingerprint(of: contacts),
                       ContactExemptions.fingerprint(of: contacts))
    }

    func testAnyChangeGivesADifferentFingerprint() {
        let original = ContactExemptions.fingerprint(of: contacts)
        let changed: [[Int64]] = [
            [],                                              // access turned off
            [12_015_550_123],                                // someone removed
            [12_015_550_123, 19_095_551_234, 19_095_551_235], // someone added
            [12_015_550_124, 19_095_551_234],                // a number edited
        ]
        for numbers in changed {
            XCTAssertNotEqual(ContactExemptions.fingerprint(of: numbers), original, "\(numbers)")
        }
    }

    func testIsTheSameInEveryLaunch() {
        // A fixed value: Swift's Hasher would give a different one every run,
        // and every launch would then look like a change to contacts.
        XCTAssertEqual(ContactExemptions.fingerprint(of: []), "cbf29ce484222325-0")
    }
}
