import Foundation

/// The decision layer: settings + device + frontmost app -> which axes to invert.
///
/// Kept entirely free of CoreGraphics so it can be exercised directly by tests
/// (see `ScrollTransformerTests`) rather than by generating physical scroll events.
public enum ScrollTransformer {

    /// Resolution order, most specific first:
    /// 1. master switch off        -> never flip
    /// 2. an enabled app rule      -> it wins outright
    /// 3. the device class rule    -> the normal path
    public static func flip(
        device: PointingDeviceType,
        frontmostBundleID: String?,
        settings: ScrollSettings
    ) -> AxisFlip {
        guard settings.isEnabled else { return .none }

        let deviceFlip = settings.rule(for: device).flip()

        guard let appRule = settings.appRule(for: frontmostBundleID) else {
            return deviceFlip
        }

        switch appRule.action {
        case .passthrough:
            return .none
        case .forceNatural:
            return .none
        case .forceReverse:
            // Honour the axes the device rule is configured to act on, but force
            // them on. A rule that acts on no axis stays a no-op rather than
            // silently inventing horizontal reversal the user never asked for.
            let rule = settings.rule(for: device)
            let anyAxis = rule.reverseVertical || rule.reverseHorizontal
            return anyAxis
                ? AxisFlip(vertical: rule.reverseVertical, horizontal: rule.reverseHorizontal)
                : AxisFlip(vertical: true, horizontal: false)
        }
    }

    /// Convenience used by tests: decide and apply in one step.
    public static func transform(
        delta: ScrollDelta,
        device: PointingDeviceType,
        frontmostBundleID: String?,
        settings: ScrollSettings
    ) -> ScrollDelta {
        delta.applying(flip(device: device, frontmostBundleID: frontmostBundleID, settings: settings))
    }
}
