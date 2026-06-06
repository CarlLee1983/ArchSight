import ArchSightKit
import SwiftUI

/// Compact reading controls (theme, font size, line spacing) shared by the
/// Markdown preview and the code view. Binds the shared store so every surface
/// and the Settings window stay in sync.
struct ReadingControlsView: View {
    @Environment(ReadingPreferencesStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Picker("Theme", selection: themeBinding) {
                ForEach(ReadingThemeID.allCases, id: \.self) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .help("Reading theme")

            HStack(spacing: 2) {
                Button { store.decreaseFont() } label: { Image(systemName: "textformat.size.smaller") }
                    .disabled(store.preferences.fontScale <= ReadingPreferences.minFontScale)
                    .help(ShortcutCatalog.tooltip("Decrease text size", "decreaseText"))
                Button { store.increaseFont() } label: { Image(systemName: "textformat.size.larger") }
                    .disabled(store.preferences.fontScale >= ReadingPreferences.maxFontScale)
                    .help(ShortcutCatalog.tooltip("Increase text size", "increaseText"))
            }

            Picker("Line spacing", selection: lineSpacingBinding) {
                Image(systemName: "text.justify").tag(LineSpacing.compact)
                Image(systemName: "text.justifyleft").tag(LineSpacing.normal)
                Image(systemName: "list.bullet").tag(LineSpacing.relaxed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .help("Line spacing")
        }
    }

    private var themeBinding: Binding<ReadingThemeID> {
        Binding(get: { store.preferences.theme }, set: { store.setTheme($0) })
    }

    private var lineSpacingBinding: Binding<LineSpacing> {
        Binding(get: { store.preferences.lineSpacing }, set: { store.setLineSpacing($0) })
    }

}
