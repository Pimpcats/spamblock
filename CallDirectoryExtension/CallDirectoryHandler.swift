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

        // The list saved in the App Group when there is one, otherwise the
        // compiled-in list — the only source when no App Group is provisioned.
        // See Shared/BlockedAreaCodes.swift.
        //
        // Falling back when nothing was ever saved, not just when there's no
        // container: a sideloader can leave the App Group entitlement in place
        // so a container exists while the rules file inside it never does. A
        // list that was saved empty, though, is someone clearing it on
        // purpose, and blocks nothing.
        let store = RuleStore.shared
        let saved = store.loadSaved()
        let listed = saved.map { $0.filter(\.isEnabled).map(\.prefix) } ?? BlockedAreaCodes.prefixes

        // One extension can't hold a whole area code, so several copies of this
        // one each carry a part of the list. They all compute the same split and
        // keep only their own part; see ExtensionSlice.
        let slice = ExtensionSlice.current
        let plan = NumberPlan(prefixes: NumberPlan.slices(of: listed, count: slice.count)[slice.index])

        // Read here rather than being handed the numbers by the app: that would
        // need an App Group, which a free Apple ID can't provision. Empty when
        // permission was never granted, which blocks the area code outright —
        // the app says so plainly rather than leaving it to be discovered.
        let exempt = ContactExemptions.sortedNumbers()

        let exempted = plan.exemptedCount(from: exempt)
        let source = saved == nil ? "built-in list" : "app group"
        logger.log("""
            Part \(slice.number) of \(slice.count): loading \(plan.entryCount) entries \
            from \(source, privacy: .public), \
            exempting \(exempted) of \(exempt.count) contacts
            """)

        // Tells the app which list this part read, through the same container
        // it read from; see RuleStore.PartReport.
        if store.isAvailable {
            let report = RuleStore.PartReport(
                prefixes: NumberPlan(prefixes: listed).prefixes,
                entries: plan.entryCount - exempted,
                loadedAt: Date()
            )
            do {
                try store.saveReport(report, part: slice.number)
            } catch {
                logger.error("Couldn’t save the load report: \(error.localizedDescription, privacy: .public)")
            }
        }

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
