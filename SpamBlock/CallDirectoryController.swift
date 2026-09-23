import CallKit
import Combine
import Foundation

/// Talks to `CXCallDirectoryManager`: whether each part of the extension is
/// switched on in Settings, and asking iOS to reload them after a change.
///
/// The block list is split across several extensions (see ExtensionSlice).
/// Each has its own switch in Settings and its own load, and either can fail
/// independently, so state is tracked per part and a failure names its part.
@MainActor
final class CallDirectoryController: ObservableObject {

    typealias Part = AppConfiguration.EmbeddedExtension

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

    /// The Settings switch for each part, by part number.
    @Published private(set) var partStatus: [Int: Status] = [:]
    /// The part being loaded while a reload is under way.
    @Published private(set) var reloadingPart: Int?
    @Published var message: Message?

    let parts = AppConfiguration.embeddedExtensions
    private var manager: CXCallDirectoryManager { .sharedInstance }

    var isReloading: Bool { reloadingPart != nil }

    /// On only when every part is on — each blocks a different range, so one
    /// switched off leaves a gap. Off as soon as any part is known to be off.
    var status: Status {
        let states = parts.map { status(ofPart: $0.slice.number) }
        guard !states.isEmpty else { return .unknown }
        if states.allSatisfy({ $0 == .enabled }) { return .enabled }
        if states.contains(.disabled) { return .disabled }
        return .unknown
    }

    func status(ofPart number: Int) -> Status {
        partStatus[number] ?? .unknown
    }

    func refreshStatus() {
        for part in parts {
            manager.getEnabledStatusForExtension(withIdentifier: part.bundleIdentifier) { [weak self] status, error in
                Task { @MainActor in
                    guard let self else { return }
                    let number = part.slice.number
                    if let error {
                        self.partStatus[number] = .unknown
                        self.message = Message(kind: .failure, text: self.describe(error, part: part))
                        return
                    }
                    switch status {
                    case .enabled: self.partStatus[number] = .enabled
                    case .disabled: self.partStatus[number] = .disabled
                    case .unknown: self.partStatus[number] = .unknown
                    @unknown default: self.partStatus[number] = .unknown
                    }
                }
            }
        }
    }

    /// Reloads every part, one after another. The rules must already be saved:
    /// each extension reads them itself, and nothing is passed in this call.
    ///
    /// One at a time because each part is up to a couple of million entries,
    /// and iOS gives the phone only so much memory for all of them together.
    /// Carries on past a failure so the other parts still update, then reports
    /// the first failure along with which part it came from.
    func reload(onSuccess: @escaping () -> Void) {
        guard !isReloading, !parts.isEmpty else { return }
        message = nil
        reload(at: 0, failures: [], onSuccess: onSuccess)
    }

    private func reload(
        at position: Int,
        failures: [(part: Part, error: Error)],
        onSuccess: @escaping () -> Void
    ) {
        guard position < parts.count else {
            reloadingPart = nil
            if let first = failures.first {
                let others = failures.count - 1
                let also = others == 0 ? "" : others == 1
                    ? " One other part also failed."
                    : " \(others) other parts also failed."
                message = Message(kind: .failure, text: describe(first.error, part: first.part) + also)
            } else {
                message = Message(kind: .success, text: "Your block list is live.")
                onSuccess()
            }
            refreshStatus()
            return
        }

        let part = parts[position]
        reloadingPart = part.slice.number
        manager.reloadExtension(withIdentifier: part.bundleIdentifier) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                var failures = failures
                if let error {
                    failures.append((part: part, error: error))
                }
                self.reload(at: position + 1, failures: failures, onSuccess: onSuccess)
            }
        }
    }

    /// Opens Settings directly at Call Blocking & Identification, which is
    /// several taps deep and hard to describe otherwise.
    func openSettings() {
        manager.openSettings { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self else { return }
                self.message = Message(kind: .failure, text: self.describe(error, part: nil))
            }
        }
    }

    /// Names the part when there is more than one, since "switched off" or
    /// "too large" is only actionable once you know which of four it means.
    private func describe(_ error: Error, part: Part?) -> String {
        let reason = describe(error)
        guard let part, part.slice.count > 1 else { return reason }
        return "SpamBlock \(part.slice.number) of \(part.slice.count): \(reason)"
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
            // Two sideloading choices end here and need different fixes: the
            // extension was stripped out, or it is still inside the app but was
            // signed with the app's own profile, which doesn't match its bundle
            // ID — so iOS never registers it.
            return AppConfiguration.isExtensionEmbedded
                ? "The extension is inside SpamBlock, but iOS didn’t register it. That happens when it’s signed with the app’s profile instead of its own — reinstall and choose “Keep App Extensions (Register App ID for Each Extension)”."
                : "iOS has no call blocking extension for SpamBlock. It was removed during sideloading — reinstall and keep app extensions, choosing “Register App ID for Each Extension”."
        case .extensionDisabled:
            return "Switched off. Turn it on under Settings › Apps › Phone › Call Blocking & Identification."
        case .maximumEntriesExceeded:
            return "More numbers than iOS will accept in one extension. The list needs splitting across more parts."
        case .loadingInterrupted:
            return "iOS stopped loading it before it finished, usually because it was too large."
        case .entriesOutOfOrder:
            return "iOS rejected the list because the numbers weren’t in ascending order. That’s a bug in SpamBlock, not something you did."
        case .duplicateEntries:
            return "iOS rejected the list because it contained the same number twice. That’s a bug in SpamBlock, not something you did."
        case .unexpectedIncrementalRemoval:
            return "iOS asked for a full reload but got a partial one. Try updating again."
        case .currentlyLoading:
            return "iOS is still loading the previous version. Give it a moment and try again."
        case .unknown:
            return "iOS reported an unspecified problem loading the list."
        @unknown default:
            return error.localizedDescription
        }
    }
}
