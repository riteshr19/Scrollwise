import Foundation

/// How a scroll event's originating hardware is classified at event time.
///
/// Important limitation, documented deliberately: macOS does **not** expose a
/// per-device identifier on `CGEvent` scroll events through any public API. What
/// *is* reliably derivable is the device *class*, from the event's own traits.
/// Rules are therefore keyed by class, not by individual serial number.
/// `HIDDeviceInventory` supplies real hardware names for display only.
public enum PointingDeviceType: String, Codable, Sendable, CaseIterable, Hashable {
    case trackpad
    case mouse
    case tablet
    /// Nothing in the event distinguished it. Treated as `mouse` by
    /// `ScrollSettings.rule(for:)` — the safe default, because a device that
    /// emits no phase information behaves like a wheel.
    case unknown

    public var displayName: String {
        switch self {
        case .trackpad: "Trackpad"
        case .mouse: "Mouse"
        case .tablet: "Tablet"
        case .unknown: "Other"
        }
    }

    /// The class whose rule governs this device when no rule of its own applies.
    public var resolvedForRules: PointingDeviceType {
        self == .unknown ? .mouse : self
    }
}
