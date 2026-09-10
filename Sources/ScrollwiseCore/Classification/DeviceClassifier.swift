import Foundation

/// Decides what kind of hardware produced a scroll event, from the event alone.
///
/// Why this and not IOHID: `CGEvent` scroll events reaching an event tap carry no
/// public device identifier, so the originating device cannot be looked up. What
/// they *do* carry is enough to separate the classes reliably:
///
/// - A trackpad (and Magic Mouse's touch surface) drives a **continuous**,
///   phase-bearing gesture: `isContinuous` is set and a phase is present.
/// - Inertial scrolling after the fingers lift keeps `isContinuous` but reports a
///   **momentum** phase instead. It is still the trackpad.
/// - A conventional wheel emits **discrete**, phase-less clicks.
/// - Tablet pucks announce themselves through the NSEvent subtype.
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

    /// Where the event sits in its gesture, which the momentum latch needs.
    public static func phase(_ traits: ScrollEventTraits, isGestureStart: Bool, isGestureEnd: Bool) -> GesturePhase {
        if traits.hasMomentumPhase { return .momentum }
        guard traits.hasPhase else { return .discrete }
        if isGestureStart { return .began }
        if isGestureEnd { return .ended }
        return .changed
    }
}
