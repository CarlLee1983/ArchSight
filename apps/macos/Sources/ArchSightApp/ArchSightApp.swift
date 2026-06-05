import ArchSightKit
import SwiftUI

@main
struct ArchSightApp: App {
    @State private var readingPreferences = ReadingPreferencesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(readingPreferences)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            ReadingSettingsView()
                .environment(readingPreferences)
        }
    }
}
