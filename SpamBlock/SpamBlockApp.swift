import SwiftUI

@main
struct SpamBlockApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Asking whenever the app goes to the background keeps a refresh
        // queued; a new request replaces the pending one.
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                KnownSpamRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(KnownSpamRefresh.taskIdentifier)) {
            await KnownSpamRefresh.run()
        }
    }
}
