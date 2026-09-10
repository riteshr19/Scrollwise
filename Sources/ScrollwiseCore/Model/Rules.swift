import Foundation

/// Per-device-class direction rule. `reversed` means "invert what macOS delivers".
public struct DeviceRule: Codable, Equatable, Sendable, Identifiable {
    public var device: PointingDeviceType
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    /// Off means this class is passed through untouched even while the app is enabled.
    public var isEnabled: Bool

    public var id: PointingDeviceType { device }

    public init(
        device: PointingDeviceType,
        reverseVertical: Bool,
        reverseHorizontal: Bool = false,
        isEnabled: Bool = true
    ) {
        self.device = device
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.isEnabled = isEnabled
    }

    public func flip() -> AxisFlip {
        guard isEnabled else { return .none }
        return AxisFlip(vertical: reverseVertical, horizontal: reverseHorizontal)
    }
}

/// What an app-specific override does when its app is frontmost.
public enum AppRuleAction: String, Codable, Sendable, CaseIterable {
    /// Pass every scroll through untouched — "Skip in this app".
    case passthrough
    /// Force reversal regardless of the device rule.
    case forceReverse
    /// Force no reversal regardless of the device rule.
    case forceNatural

    public var displayName: String {
        switch self {
        case .passthrough: "Leave alone"
        case .forceReverse: "Always reverse"
        case .forceNatural: "Never reverse"
        }
    }
}

public struct AppRule: Codable, Equatable, Sendable, Identifiable {
    public var bundleIdentifier: String
    public var displayName: String
    public var action: AppRuleAction
    public var isEnabled: Bool

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        displayName: String,
        action: AppRuleAction = .passthrough,
        isEnabled: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// A named set of device rules the user can switch between (the 1d segmented control).
public struct Profile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var deviceRules: [DeviceRule]

    public init(id: UUID = UUID(), name: String, deviceRules: [DeviceRule]) {
        self.id = id
        self.name = name
        self.deviceRules = deviceRules
    }

    public func rule(for device: PointingDeviceType) -> DeviceRule? {
        let wanted = device.resolvedForRules
        return deviceRules.first { $0.device == wanted }
    }

    /// Returns a copy with one device's rule replaced. Never mutates the receiver.
    public func replacing(_ rule: DeviceRule) -> Profile {
        var copy = self
        if let index = copy.deviceRules.firstIndex(where: { $0.device == rule.device }) {
            copy.deviceRules[index] = rule
        } else {
            copy.deviceRules.append(rule)
        }
        return copy
    }
}

// MARK: - Decoding
//
// Forgiving for the same reason as `ScrollSettings`: these are read back from
// disk. Only the field that gives an element its identity is required; an
// element without one is dropped by the enclosing `LossyArray`.

extension DeviceRule {
    enum CodingKeys: String, CodingKey {
        case device, reverseVertical, reverseHorizontal, isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            device: try container.decode(PointingDeviceType.self, forKey: .device),
            reverseVertical: container.lenient(Bool.self, .reverseVertical) ?? false,
            reverseHorizontal: container.lenient(Bool.self, .reverseHorizontal) ?? false,
            isEnabled: container.lenient(Bool.self, .isEnabled) ?? true
        )
    }
}

extension AppRule {
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier, displayName, action, isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.init(
            bundleIdentifier: bundleIdentifier,
            displayName: container.lenient(String.self, .displayName) ?? bundleIdentifier,
            // An action this build does not know — written by a newer one —
            // becomes "leave alone", the one choice that can never make
            // scrolling behave worse than macOS does on its own.
            action: container.lenient(AppRuleAction.self, .action) ?? .passthrough,
            isEnabled: container.lenient(Bool.self, .isEnabled) ?? true
        )
    }
}

extension Profile {
    enum CodingKeys: String, CodingKey {
        case id, name, deviceRules
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: container.lenient(String.self, .name) ?? "Profile",
            deviceRules: container.lenient(LossyArray<DeviceRule>.self, .deviceRules)?.elements
                ?? SettingsDefaults.deviceRules
        )
    }
}
