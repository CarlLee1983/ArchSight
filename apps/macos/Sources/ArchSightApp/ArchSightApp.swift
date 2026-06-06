import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()
    @State private var recentFolders = RecentFoldersStore()
    @State private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
                .environment(recentFolders)
                .environment(appCore)
                .task { appCore.connectIfNeeded() }
        }
        .commands {
            WorkspaceMenuCommands(readingStore: readingPreferences, recentStore: recentFolders)
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
