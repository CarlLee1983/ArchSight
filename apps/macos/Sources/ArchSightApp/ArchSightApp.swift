import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()
    @State private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
                .environment(appCore)
                .task { appCore.connectIfNeeded() }
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
