import ArchSightKit
import SwiftUI

struct ReadingSettingsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    var body: some View {
        Text("Reading settings")
            .padding()
            .frame(width: 360, height: 200)
    }
}
