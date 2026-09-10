import Foundation

/// Persists `ScrollSettings` as a single JSON blob in `UserDefaults`.
///
/// One blob rather than scattered booleans, so a save is atomic: the engine can
/// never observe half of a change. Reads that fail fall back to defaults instead
/// of throwing, because a settings problem must not stop scrolling from working.
public final class SettingsStore: @unchecked Sendable {

    public static let storageKey = "settings.v1"
    /// Where a blob this build could not read is kept, so falling back to
    /// defaults — whose next save overwrites `storageKey` — does not destroy it.
    /// A store written by a newer version and then opened by an older one is
    /// the realistic way to get here.
    public static let unreadableBackupKey = "settings.v1.unreadable"

    // UserDefaults is documented as thread-safe; it simply predates Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Always returns settings the engine can act on: decoded leniently,
    /// migrated, then normalized, or the shipped defaults if nothing is readable.
    public func load() -> ScrollSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return SettingsDefaults.settings
        }
        do {
            let decoded = try JSONDecoder().decode(ScrollSettings.self, from: data)
            return migrate(decoded).normalized()
        } catch {
            defaults.set(data, forKey: Self.unreadableBackupKey)
            Log.settings.error("Settings unreadable, falling back to defaults (original kept under \(Self.unreadableBackupKey, privacy: .public)): \(error.localizedDescription, privacy: .public)")
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

    /// Brings a payload to the current schema.
    ///
    /// Every change so far has been additive, and the decoder supplies a default
    /// for any field that is missing, so there is nothing to transform yet. The
    /// first change that is not additive belongs here, keyed on `schemaVersion`.
    /// A store from a *newer* schema is read for what this build understands.
    private func migrate(_ settings: ScrollSettings) -> ScrollSettings {
        guard settings.schemaVersion != ScrollSettings.currentSchemaVersion else { return settings }
        var migrated = settings
        migrated.schemaVersion = ScrollSettings.currentSchemaVersion
        Log.settings.info("Read settings written with schema \(settings.schemaVersion) as schema \(ScrollSettings.currentSchemaVersion)")
        return migrated
    }
}
