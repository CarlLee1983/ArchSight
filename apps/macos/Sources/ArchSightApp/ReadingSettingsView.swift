import ArchSightKit
import SwiftUI

struct ReadingSettingsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    private static let sampleMarkdown = """
    # Sample heading

    Body text with **bold** and `inline code`.

    > A short blockquote.
    """

    var body: some View {
        Form {
            Picker("Theme", selection: themeBinding) {
                ForEach(ReadingThemeID.allCases, id: \.self) { id in
                    Text(id.displayName).tag(id)
                }
            }

            Stepper(
                value: fontIndexBinding,
                in: 0...(ReadingPreferences.fontScaleSteps.count - 1)
            ) {
                Text(String(format: "Text size: %.0f%%", store.preferences.fontScale * 100))
            }

            Picker("Line spacing", selection: lineSpacingBinding) {
                Text("Compact").tag(LineSpacing.compact)
                Text("Normal").tag(LineSpacing.normal)
                Text("Relaxed").tag(LineSpacing.relaxed)
            }

            Section("Preview") {
                MarkdownPreviewView(
                    content: Self.sampleMarkdown,
                    preferences: store.preferences
                )
                .frame(height: 160)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }

    private var themeBinding: Binding<ReadingThemeID> {
        Binding(get: { store.preferences.theme }, set: { store.setTheme($0) })
    }

    private var lineSpacingBinding: Binding<LineSpacing> {
        Binding(get: { store.preferences.lineSpacing }, set: { store.setLineSpacing($0) })
    }

    /// Maps the discrete scale steps onto a Stepper index so each tick lands on
    /// a valid step and persists through the store.
    private var fontIndexBinding: Binding<Int> {
        Binding(
            get: {
                ReadingPreferences.fontScaleSteps.firstIndex(of: store.preferences.fontScale) ?? 1
            },
            set: { newIndex in
                let current = ReadingPreferences.fontScaleSteps.firstIndex(of: store.preferences.fontScale) ?? 1
                if newIndex > current { store.increaseFont() }
                else if newIndex < current { store.decreaseFont() }
            }
        )
    }
}
