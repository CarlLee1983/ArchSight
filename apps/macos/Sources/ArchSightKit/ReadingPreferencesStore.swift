import Foundation
import Observation

/// Observable, persistent holder for `ReadingPreferences`. Mutations route
/// through the explicit setters so persistence stays in one place (no reliance
/// on `didSet` semantics under the `@Observable` macro).
@Observable
public final class ReadingPreferencesStore {
    public private(set) var preferences: ReadingPreferences

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "reading.preferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.loadPreferences(from: defaults)
    }

    public func setTheme(_ id: ReadingThemeID) {
        update { $0.theme = id }
    }

    public func setLineSpacing(_ spacing: LineSpacing) {
        update { $0.lineSpacing = spacing }
    }

    public func increaseFont() {
        preferences = preferences.increasedFont()
        persist()
    }

    public func decreaseFont() {
        preferences = preferences.decreasedFont()
        persist()
    }

    private func update(_ mutate: (inout ReadingPreferences) -> Void) {
        var copy = preferences
        mutate(&copy)
        preferences = copy
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadPreferences(from defaults: UserDefaults) -> ReadingPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ReadingPreferences.self, from: data)
        else {
            return .default
        }
        return decoded.normalized()
    }
}
