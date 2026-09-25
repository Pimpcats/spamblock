import CallKit
import Combine
import Foundation

/// The Known spam extension as the app sees it: whether it's switched on,
/// when it last loaded the list, what the published list holds, and reloading
/// it on request.
///
/// The app can't see what the extension actually loaded — there's no App
/// Group to report it through on a free Apple ID — so it describes the list
/// from the small info file published alongside it, and trusts a successful
/// reload to mean the extension downloaded it, or fell back to its saved copy.
@MainActor
final class KnownSpamController: ObservableObject {

    typealias Status = CallDirectoryController.Status
    typealias Message = CallDirectoryController.Message

    @Published private(set) var status: Status = .unknown
    @Published private(set) var isReloading = false
    @Published private(set) var loadedAt: Date? = KnownSpamRefresh.lastLoaded
    @Published private(set) var info: KnownSpamList.Info?
    @Published var message: Message?

    let identifier = AppConfiguration.knownSpamExtensionIdentifier
    var isInstalled: Bool { identifier != nil }

    private var manager: CXCallDirectoryManager { .sharedInstance }

    /// The address book as last read by the app, for telling whether the
    /// extension's last load skipped the contacts that exist now.
    private var contactsFingerprint: String?

    private var contactsChangedSinceLoad: Bool {
        guard let current = contactsFingerprint else { return false }
        return AppliedContacts.knownSpam != current
    }

    /// Takes each fresh reading of the address book, and reloads the list if
    /// contacts have changed since it last loaded — the extension skips them
    /// when it loads, so a new contact is only safe from the list after that.
    func contactsDidChange(fingerprint: String) {
        contactsFingerprint = fingerprint
        guard AppliedContacts.knownSpam != nil else {
            // The first reading since this existed: treat what's loaded as
            // current rather than reloading on a guess.
            AppliedContacts.knownSpam = fingerprint
            return
        }
        if status == .enabled && contactsChangedSinceLoad {
            reload(announce: false)
        }
    }

    /// Re-reads everything, and reloads the list when the extension is
    /// switched on and its last load is out of date, or predates a change to
    /// contacts — so opening the app is enough to catch up, whatever iOS did
    /// about background time.
    func refresh() {
        loadedAt = KnownSpamRefresh.lastLoaded
        fetchInfo()

        guard let identifier = identifier else { return }
        manager.getEnabledStatusForExtension(withIdentifier: identifier) { [weak self] status, error in
            Task { @MainActor in
                guard let self else { return }
                switch (error, status) {
                case (.some, _): self.status = .unknown
                case (nil, .enabled): self.status = .enabled
                case (nil, .disabled): self.status = .disabled
                default: self.status = .unknown
                }
                if self.status == .enabled && (KnownSpamRefresh.isStale || self.contactsChangedSinceLoad) {
                    self.reload(announce: false)
                }
            }
        }
    }

    /// Reloads the extension, which downloads the current list. `announce`
    /// is false for the automatic reload on opening, which reports failures
    /// but doesn't celebrate routine success.
    func reload(announce: Bool = true) {
        guard let identifier = identifier, !isReloading else { return }
        isReloading = true
        if announce { message = nil }

        manager.reloadExtension(withIdentifier: identifier) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isReloading = false
                if let error {
                    self.message = Message(kind: .failure, text: Self.describe(error))
                } else {
                    KnownSpamRefresh.recordLoaded()
                    self.loadedAt = KnownSpamRefresh.lastLoaded
                    if let fingerprint = self.contactsFingerprint {
                        AppliedContacts.knownSpam = fingerprint
                    }
                    if announce {
                        self.message = Message(kind: .success, text: "Known spam list updated.")
                    }
                }
                self.fetchInfo()
            }
        }
    }

    /// Best effort: without it the section just doesn't show the list's size.
    private func fetchInfo() {
        Task {
            if let info = try? await KnownSpamList.fetchInfo() {
                self.info = info
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        // The extension's own error, if CallKit passes it through intact.
        if error.domain == KnownSpamList.errorDomain {
            return error.localizedDescription
        }
        // CallKit may instead report the extension cancelling as a generic
        // failure. For this extension that nearly always means the download.
        if error.domain == CXErrorDomainCallDirectoryManager,
           let code = CXErrorCodeCallDirectoryManagerError.Code(rawValue: error.code),
           code == .unknown || code == .loadingInterrupted {
            return "Couldn’t load the list. The first load needs an internet connection; after that SpamBlock keeps a copy. Try again in a moment."
        }
        return CallDirectoryController.describe(error)
    }
}
