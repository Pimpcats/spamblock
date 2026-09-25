import CallKit
import Foundation
import os

/// The "SpamBlock — Known spam" extension: blocks numbers reported to the FTC
/// as spam, from the list the spamblock-data repository publishes.
///
/// Unlike the area-code parts, the list isn't known when the app is built, so
/// this downloads it every time iOS runs it — when the app asks for a reload,
/// after a restart, when it's switched on — and falls back to the last copy
/// that downloaded cleanly. It downloads the list itself because the app can't
/// hand it over: that would need an App Group, which a free Apple ID can't
/// provision.
final class KnownSpamHandler: CXCallDirectoryProvider {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpamBlock",
        category: "KnownSpam"
    )

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        Task {
            await self.load(into: context)
        }
    }

    private func load(into context: CXCallDirectoryExtensionContext) async {
        let loaded: KnownSpamList.Loaded
        do {
            loaded = try await KnownSpamList.load(
                download: { try await self.download() },
                cache: KnownSpamList.Cache.standard
            )
        } catch {
            // Cancelling keeps whatever iOS already holds from the last load,
            // rather than replacing it with nothing.
            logger.error("No list to load: \(error.localizedDescription, privacy: .public)")
            context.cancelRequest(withError: error)
            return
        }
        if let error = loaded.downloadError {
            logger.error("Download failed, loading the saved copy: \(error.localizedDescription, privacy: .public)")
        }
        submit(loaded, to: context)
    }

    /// Hands the numbers to CallKit and completes the request. Synchronous on
    /// purpose: inside an async function, `completeRequest()` resolves to its
    /// async overload, which waits on iOS for no benefit here.
    private func submit(_ loaded: KnownSpamList.Loaded, to context: CXCallDirectoryExtensionContext) {
        // Read here for the same reason as the list: nothing can be passed in.
        let exempt = ContactExemptions.sortedNumbers()

        // On an incremental request iOS keeps the previous entries, so they're
        // cleared first; on a full one there are none and clearing is an error.
        if context.isIncremental {
            context.removeAllBlockingEntries()
        }

        let skipped = KnownSpamList.forEachEntry(in: loaded.numbers, exempt: exempt) { number in
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }

        let source = loaded.source == .downloaded ? "download" : "saved copy"
        logger.log("""
            Loading \(loaded.numbers.count - skipped) known-spam numbers \
            from the \(source, privacy: .public), \
            skipping \(skipped) in contacts
            """)
        context.completeRequest()
    }

    private func download() async throws -> Data {
        // Ephemeral: nothing about this request is worth keeping on disk, and
        // the list itself is kept deliberately, in KnownSpamList.Cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await KnownSpamList.download(session: session)
    }
}

extension KnownSpamHandler: CXCallDirectoryExtensionContextDelegate {

    /// Called when iOS rejects the directory. This log is all there is when iOS
    /// reloads the extension on its own, with no app running.
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        logger.error("Known spam request failed: \(error.localizedDescription, privacy: .public)")
    }
}
