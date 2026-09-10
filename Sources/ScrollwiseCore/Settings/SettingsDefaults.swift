import Foundation

/// The shipped defaults.
///
/// Chosen to match what someone installing a scroll reverser is asking for, while
/// leaving anything ambiguous switched off:
/// - **Trackpad: not reversed.** macOS's own natural scrolling already suits
///   trackpads; reversing it by default would fight the gesture most people like.
/// - **Mouse: reversed.** This is the reason the app exists — a wheel that follows
///   the trackpad's natural direction is the complaint being solved.
/// - **Vertical only.** Horizontal reversal is off everywhere until asked for,
///   because flipping it silently breaks timeline and canvas apps.
public enum SettingsDefaults {

    public static let defaultProfileID = UUID(uuidString: "0E7A2C1E-0000-4000-A000-000000000001")!

    public static var deviceRules: [DeviceRule] {
        [
            DeviceRule(device: .trackpad, reverseVertical: false, reverseHorizontal: false),
            DeviceRule(device: .mouse, reverseVertical: true, reverseHorizontal: false),
            // Enabled like the others. `reverseVertical` is false, so a tablet
            // is still not reversed until the user asks — but the rule has to be
            // enabled for the Direction control to be live. Nothing in the UI
            // sets `isEnabled`, so shipping a rule disabled makes it permanently
            // unreachable, exactly the dead end the login item used to have.
            DeviceRule(device: .tablet, reverseVertical: false, reverseHorizontal: false),
        ]
    }

    public static var profile: Profile {
        Profile(id: defaultProfileID, name: "Default", deviceRules: deviceRules)
    }

    public static var settings: ScrollSettings {
        ScrollSettings(
            isEnabled: true,
            profiles: [profile],
            activeProfileID: defaultProfileID,
            appRules: [],
            launchAtLogin: false,
            defaultForNewDevices: DeviceRule(device: .mouse, reverseVertical: true)
        )
    }
}
