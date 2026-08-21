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
            exemptedCount = 0
            return
        }

        // Walking the address book is not instant on a large one, and this runs
        // every time the app comes to the front, so it stays off the main
        // thread. Only the count comes back.
        Task {
            let numbers = await Task.detached(priority: .utility) {
                ContactExemptions.sortedNumbers()
            }.value
            self.exemptedCount = plan.exemptedCount(from: numbers)
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
