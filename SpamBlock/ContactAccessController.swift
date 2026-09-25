import Contacts
import Combine
import Foundation

/// Owns the Contacts permission, which the extension depends on but can't ask
/// for itself — iOS launches it in the background, where there is nobody to
/// answer a prompt. So the app asks, and the extension reads the result.
@MainActor
final class ContactAccessController: ObservableObject {

    enum Status: Equatable {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var status: Status = .notDetermined
    /// How many contacts the current block list would otherwise have caught.
    @Published private(set) var exemptedCount = 0
    /// Fingerprints of the numbers the extensions skip when they load: the
    /// contacts in a blocked area code, which the area-code parts skip, and
    /// all contacts, which Known spam skips. Nil until the address book has
    /// been read. Compared with `AppliedContacts` to tell when a reload is
    /// needed for a contact to ring through.
    @Published private(set) var planFingerprint: String?
    @Published private(set) var allFingerprint: String?

    private let store = CNContactStore()

    func refresh(against plan: NumberPlan) {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            status = .notDetermined
        case .denied, .restricted:
            status = .denied
        default:
            status = .granted
        }

        guard status == .granted else {
            // The extensions can't read contacts either, so they skip none.
            exemptedCount = 0
            planFingerprint = ContactExemptions.fingerprint(of: [])
            allFingerprint = planFingerprint
            return
        }

        // Walking the address book is not instant on a large one, and this runs
        // every time the app comes to the front, so it stays off the main
        // thread. Only the count and fingerprints come back.
        Task {
            let numbers = await Task.detached(priority: .utility) {
                ContactExemptions.sortedNumbers()
            }.value
            self.exemptedCount = plan.exemptedCount(from: numbers)
            self.planFingerprint = ContactExemptions.fingerprint(of: numbers.filter(plan.covers))
            self.allFingerprint = ContactExemptions.fingerprint(of: numbers)
        }
    }

    /// Takes the plan by value: granting permission doesn't change which
    /// numbers are blocked, only how many contacts are spared, so there is
    /// nothing to re-read afterwards.
    func requestAccess(against plan: NumberPlan) {
        store.requestAccess(for: .contacts) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh(against: plan)
            }
        }
    }
}
