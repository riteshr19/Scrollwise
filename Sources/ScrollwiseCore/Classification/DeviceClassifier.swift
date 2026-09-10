import Foundation

/// Decides what kind of hardware produced a scroll event, from the event alone.
///
/// Why this and not IOHID: `CGEvent` scroll events reaching an event tap carry no
/// public device identifier, so the originating device cannot be looked up. What
/// they *do* carry is enough to separate the classes:
///
/// - A trackpad drives a **continuous**, phase-bearing gesture. So does the touch
///   surface of a Magic Mouse, which is why a Magic Mouse follows the Trackpad
///   rule — the event gives no way to tell the two apart.
/// - Inertial scrolling after the fingers lift reports a **momentum** phase
///   instead. It is still the same touch surface.
/// - A conventional wheel emits **discrete**, phase-less clicks. A high-resolution
///   wheel is continuous but still phase-less, and is still a mouse.
/// - A tablet pointer marks its events with a tablet mouse subtype.
///
/// Anything that matches none of these falls back to the mouse rule, the safe
/// default: a device that reports no phase behaves like a wheel.
///
/// This is a pure function so every branch is unit-testable.
public enum DeviceClassifier {

    public static func classify(_ traits: ScrollEventTraits) -> PointingDeviceType {
        if traits.isTabletPointer { return .tablet }

        // Phase information is the strongest signal: only a touch surface produces it.
        if traits.hasPhase || traits.hasMomentumPhase { return .trackpad }

        // Pixel-precise but phase-less. High-resolution wheels do this, and so do
        // some third-party drivers. It is not a touch surface, so treat it as a mouse.
        if traits.isContinuous { return .mouse }

        // Discrete, phase-less clicks — a conventional wheel.
        return .mouse
    }
}
