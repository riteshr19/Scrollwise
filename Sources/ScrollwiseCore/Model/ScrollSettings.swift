import Foundation

/// The single source of truth for everything the engine needs to decide an event.
///
/// Deliberately a value type: the event tap reads an immutable snapshot, so a
/// settings change on the main thread can never tear a decision in flight.
public struct ScrollSettings: Codable, Equatable, Sendable {
    /// The master switch. Off means every event passes through untouched.
    public var isEnabled: Bool
    public var profiles: [Profile]
    public var activeProfileID: UUID
    public var appRules: [AppRule]
    public var launchAtLogin: Bool
    /// What a newly seen device class gets before the user decides.
    public var defaultForNewDevices: DeviceRule
    /// Schema version, so `SettingsStore` can migrate rather than discard.
    public var schemaVersion: Int

    public init(
        isEnabled: Bool,
        profiles: [Profile],
        activeProfileID: UUID,
        appRules: [AppRule],
        launchAtLogin: Bool,
        defaultForNewDevices: DeviceRule,
        schemaVersion: Int = ScrollSettings.currentSchemaVersion
    ) {
        self.isEnabled = isEnabled
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.appRules = appRules
        self.launchAtLogin = launchAtLogin
        self.defaultForNewDevices = defaultForNewDevices
        self.schemaVersion = schemaVersion
    }

    public static let currentSchemaVersion = 1

    /// Never traps. `normalized()` guarantees a matching profile for anything
    /// loaded from disk; the fallbacks exist so that even a value built by hand
    /// with no profiles cannot crash the event tap, which reads this per event.
    public var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles.first ?? SettingsDefaults.profile
    }

    public func rule(for device: PointingDeviceType) -> DeviceRule {
        activeProfile.rule(for: device) ?? defaultForNewDevices
    }

    public func appRule(for bundleIdentifier: String?) -> AppRule? {
        guard let bundleIdentifier else { return nil }
        return appRules.first { $0.bundleIdentifier == bundleIdentifier && $0.isEnabled }
    }

    /// Returns a copy with the active profile's rule for one device replaced.
    public func replacingActiveRule(_ rule: DeviceRule) -> ScrollSettings {
        var copy = self
        guard let index = copy.profiles.firstIndex(where: { $0.id == activeProfileID })
        else { return copy }
        copy.profiles[index] = copy.profiles[index].replacing(rule)
        return copy
    }

    /// Repairs a value read from disk into one every surface can act on:
    /// at least one profile, an active profile that exists, and no duplicate
    /// identities for SwiftUI lists to trip over. Keeps everything usable.
    public func normalized() -> ScrollSettings {
        var copy = self
        copy.profiles = copy.profiles
            .uniqued(by: \.id)
            .map { profile in
                var repaired = profile
                repaired.deviceRules = profile.deviceRules.uniqued(by: \.device)
                return repaired
            }
        if copy.profiles.isEmpty {
            copy.profiles = [SettingsDefaults.profile]
        }
        if !copy.profiles.contains(where: { $0.id == copy.activeProfileID }) {
            copy.activeProfileID = copy.profiles[0].id
        }
        copy.appRules = copy.appRules.uniqued(by: \.bundleIdentifier)
        return copy
    }
}

// MARK: - Decoding

extension ScrollSettings {
    enum CodingKeys: String, CodingKey {
        case isEnabled, profiles, activeProfileID, appRules
        case launchAtLogin, defaultForNewDevices, schemaVersion
    }

    /// Field-by-field and forgiving. The synthesized decoder throws on any
    /// missing key, so adding one field in a later version would have made every
    /// older store unreadable and silently reset the user to defaults. Here a
    /// missing or malformed field costs that field alone.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SettingsDefaults.settings
        self.init(
            isEnabled: container.lenient(Bool.self, .isEnabled) ?? fallback.isEnabled,
            profiles: container.lenient(LossyArray<Profile>.self, .profiles)?.elements
                ?? fallback.profiles,
            activeProfileID: container.lenient(UUID.self, .activeProfileID)
                ?? fallback.activeProfileID,
            appRules: container.lenient(LossyArray<AppRule>.self, .appRules)?.elements ?? [],
            launchAtLogin: container.lenient(Bool.self, .launchAtLogin) ?? fallback.launchAtLogin,
            defaultForNewDevices: container.lenient(DeviceRule.self, .defaultForNewDevices)
                ?? fallback.defaultForNewDevices,
            // Every store ever written carries a version; one without is the first schema.
            schemaVersion: container.lenient(Int.self, .schemaVersion) ?? 1
        )
    }
}
