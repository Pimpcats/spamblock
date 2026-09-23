import CallKit
import Combine
import Foundation

/// Talks to `CXCallDirectoryManager`: whether the extension is switched on in
/// Settings, and asking iOS to reload it after the rules change.
@MainActor
final class CallDirectoryController: ObservableObject {

    enum Status: Equatable {
        case unknown
        case disabled
        case enabled
    }

    struct Message: Identifiable, Equatable {
        enum Kind { case success, failure }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var isReloading = false
    @Published var message: Message?

    private var manager: CXCallDirectoryManager { .sharedInstance }
    private var identifier: String { AppConfiguration.callDirectoryExtensionIdentifier }

    func refreshStatus() {
        manager.getEnabledStatusForExtension(withIdentifier: identifier) { [weak self] status, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = .unknown
                    self.message = Message(kind: .failure, text: self.describe(error))
                    return
                }
                switch status {
                case .enabled: self.status = .enabled
                case .disabled: self.status = .disabled
                case .unknown: self.status = .unknown
                @unknown default: self.status = .unknown
                }
            }
        }
    }

    /// Asks iOS to re-run the extension. The rules must already be saved —
    /// the extension reads them from the shared container itself, and nothing
    /// is passed across in this call.
    func reload(onSuccess: @escaping () -> Void) {
        guard !isReloading else { return }
        isReloading = true

        manager.reloadExtension(withIdentifier: identifier) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isReloading = false
                if let error {
                    self.message = Message(kind: .failure, text: self.describe(error))
                } else {
                    self.message = Message(kind: .success, text: "Your block list is live.")
                    onSuccess()
                }
                self.refreshStatus()
            }
        }
    }

    /// Opens Settings directly at Call Blocking & Identification, which is
    /// several taps deep and hard to describe otherwise.
    func openSettings() {
        manager.openSettings { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.message = Message(kind: .failure, text: self?.describe(error) ?? error.localizedDescription)
            }
        }
    }

    /// CallKit's own messages are terse and don't say what to do about it.
    private func describe(_ error: Error) -> String {
        let error = error as NSError
        guard error.domain == CXErrorDomainCallDirectoryManager,
              let code = CXErrorCodeCallDirectoryManagerError.Code(rawValue: error.code) else {
            return error.localizedDescription
        }

        switch code {
        case .noExtensionFound:
            // Two different sideloading choices end here, and they need
            // different fixes: the extension was stripped out, or it is still
            // inside the app but was signed with the app's own profile, which
            // doesn't match the extension's bundle ID — so iOS never
            // registers it.
            return AppConfiguration.isExtensionEmbedded
                ? "The call blocking extension is inside SpamBlock, but iOS didn’t register it. That happens when it’s signed with the app’s profile instead of its own — reinstall and choose “Keep App Extensions (Register App ID for Each Extension)”."
                : "iOS has no call blocking extension for SpamBlock. It was removed during sideloading — reinstall and keep app extensions, choosing “Register App ID for Each Extension”."
        case .extensionDisabled:
            return "SpamBlock is switched off in Settings › Phone › Call Blocking & Identification."
        case .maximumEntriesExceeded:
            return "The block list is too large for iOS to load. Remove an area code, or narrow one to the exchanges that actually call you."
        case .loadingInterrupted:
            return "iOS stopped loading the list before it finished, usually because it was too large. Try fewer area codes."
        case .entriesOutOfOrder:
            return "iOS rejected the list because the numbers weren’t in ascending order. That’s a bug in SpamBlock, not something you did."
        case .duplicateEntries:
            return "iOS rejected the list because it contained the same number twice. That’s a bug in SpamBlock, not something you did."
        case .unexpectedIncrementalRemoval:
            return "iOS asked for a full reload but got a partial one. Try updating again."
        case .currentlyLoading:
            return "iOS is still loading the previous version of your list. Give it a moment and try again."
        case .unknown:
            return "iOS reported an unspecified problem loading the list."
        @unknown default:
            return error.localizedDescription
        }
    }
}
