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

    public var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
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
}
