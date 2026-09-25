import BackgroundTasks
import CallKit
import Foundation

/// Keeps the known-spam list current without the app having to be opened.
///
/// The list is rebuilt daily, but only reaches the phone when the Known spam
/// extension is reloaded — and only the app can ask for that. So the app asks
/// iOS for background time roughly twice a day and reloads it then, and also
/// reloads it on opening whenever the last load is out of date. iOS decides
/// when background time actually comes, based on how the app is used, so
/// opening the app remains the dependable way to update.
enum KnownSpamRefresh {

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "spamblock.known-spam-refresh"

    /// How old a load can get before the app reloads it. Half the rebuild
    /// interval, so a daily list is never more than a day behind on a phone
    /// that iOS gives background time to, or that's opened daily.
    static let maximumAge: TimeInterval = 12 * 60 * 60

    private static let loadedAtKey = "knownSpamLoadedAt"

    /// When the extension last loaded the list at the app's request.
    static var lastLoaded: Date? {
        UserDefaults.standard.object(forKey: loadedAtKey) as? Date
    }

    static func recordLoaded(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: loadedAtKey)
    }

    static var isStale: Bool {
        guard let last = lastLoaded else { return true }
        return Date().timeIntervalSince(last) > maximumAge
    }

    /// Asks iOS for the next background run. Replaces any request already
    /// pending, so calling it often is harmless.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: maximumAge)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The background run: reloads the extension, which downloads the list.
    /// Schedules the next run first, so one that iOS cuts short still leaves
    /// another queued.
    static func run() async {
        schedule()
        guard let identifier = AppConfiguration.knownSpamExtensionIdentifier else { return }
        do {
            try await CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: identifier)
            recordLoaded()
        } catch {
            // Nobody to tell in the background. The app shows the extension's
            // state and when it last loaded the next time it's opened.
        }
    }
}
