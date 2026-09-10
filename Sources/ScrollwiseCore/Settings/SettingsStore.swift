import Foundation

/// Persists `ScrollSettings` as a single JSON blob in `UserDefaults`.
///
/// One blob rather than scattered booleans, so a save is atomic: the engine can
/// never observe half of a change. Reads that fail fall back to defaults instead
/// of throwing, because a settings problem must not stop scrolling from working.
public final class SettingsStore: @unchecked Sendable {

    public static let storageKey = "settings.v1"

    // UserDefaults is documented as thread-safe; it simply predates Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ScrollSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return SettingsDefaults.settings
        }
        do {
            let decoded = try JSONDecoder().decode(ScrollSettings.self, from: data)
            return migrate(decoded)
        } catch {
            Log.settings.error("Settings unreadable, falling back to defaults: \(error.localizedDescription, privacy: .public)")
            return SettingsDefaults.settings
        }
    }

    /// `UserDefaults.set` writes to an in-process cache and lets `cfprefsd`
    /// persist lazily — there is no synchronous disk I/O here, so no dispatch
    /// hop is warranted. Saves never originate from the event tap regardless.
    public func save(_ settings: ScrollSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.storageKey)
        } catch {
            Log.settings.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Brings an older payload up to the current schema. Additive so far, so
    /// decoding already supplies the new fields' defaults; the hook exists for
    /// the first genuinely breaking change.
    private func migrate(_ settings: ScrollSettings) -> ScrollSettings {
        guard settings.schemaVersion < ScrollSettings.currentSchemaVersion else { return settings }
        var migrated = settings
        migrated.schemaVersion = ScrollSettings.currentSchemaVersion
        Log.settings.info("Migrated settings from schema \(settings.schemaVersion) to \(ScrollSettings.currentSchemaVersion)")
        return migrated
    }
}
