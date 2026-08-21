import CallKit
import Foundation
import os

/// The Call Directory extension.
///
/// iOS — not the app — decides when to run this, out of process, and asks for
/// the complete set of numbers to block. It runs under a memory and time budget
/// that Apple doesn't publish, and when it exceeds either it is killed and the
/// whole directory is discarded. So this does as close to nothing as possible
/// besides streaming numbers into the context: no networking, no formatting, no
/// intermediate collections.
final class CallDirectoryHandler: CXCallDirectoryProvider {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpamBlock",
        category: "CallDirectory"
    )

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        // Without a provisioned App Group there is no shared container to read,
        // so the compiled-in list is the only thing available. That is the
        // normal path on a free Apple ID — see Shared/BlockedAreaCodes.swift.
        let store = RuleStore.shared
        let plan = store.isAvailable
            ? NumberPlan(rules: store.load())
            : NumberPlan(prefixes: BlockedAreaCodes.prefixes)

        // Read here rather than being handed the numbers by the app: that would
        // need an App Group, which a free Apple ID can't provision. Empty when
        // permission was never granted, which blocks the area code outright —
        // the app says so plainly rather than leaving it to be discovered.
        let exempt = ContactExemptions.sortedNumbers()

        let source = store.isAvailable ? "app group" : "built-in list"
        logger.log("""
            Loading \(plan.prefixes.count) prefixes, \(plan.entryCount) entries \
            from \(source, privacy: .public), \
            exempting \(plan.exemptedCount(from: exempt)) of \(exempt.count) contacts
            """)

        // On an incremental request iOS keeps what was supplied last time, so
        // the previous entries have to be cleared before the current list is
        // added. On a full request it has nothing yet and calling this is an
        // error, hence the check rather than clearing unconditionally.
        if context.isIncremental {
            context.removeAllBlockingEntries()
        }

        plan.forEachNumber(exempt: exempt) { number in
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }

        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {

    /// Called when iOS rejects the directory. The app surfaces the same error
    /// through `CXCallDirectoryManager`; this log is what's available when the
    /// system reloads the extension on its own schedule, with no app running.
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        logger.error("Call directory request failed: \(error.localizedDescription, privacy: .public)")
    }
}
