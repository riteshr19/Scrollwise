import Foundation

/// Holds one gesture's flip decision steady from first touch through the last
/// momentum event.
///
/// Without this, changing a setting (or switching app) mid-flick would reverse the
/// inertia but not the fingers that launched it, so the content would visibly snap
/// direction while decelerating. Latching is what makes momentum feel correct.
///
/// Not thread-safe by design: it is touched only from the event tap's run loop.
public struct GestureLatch: Sendable {
    private var latched: AxisFlip?

    public init() {}

    /// Returns the decision to use for this event, updating the latch as the
    /// gesture progresses.
    public mutating func resolve(phase: GesturePhase, proposed: AxisFlip) -> AxisFlip {
        switch phase {
        case .discrete:
            // A wheel click has no gesture around it, so it always takes the
            // live decision — and it leaves any latch alone. Clearing the latch
            // here would let one wheel tick during trackpad inertia hand the
            // rest of that inertia a different decision.
            return proposed

        case .began:
            latched = proposed
            return proposed

        case .changed, .momentum:
            // Mid-gesture and inertia inherit the decision the gesture started with.
            if let latched { return latched }
            latched = proposed
            return proposed

        case .ended:
            // Keep the latch: momentum events arrive *after* .ended and must match.
            if let latched { return latched }
            latched = proposed
            return proposed
        }
    }

    /// The whole per-event step the tap performs: resolve against the latch,
    /// then release it if this is the last event the gesture can produce.
    public mutating func resolve(_ fields: RawScrollFields, proposed: AxisFlip) -> AxisFlip {
        let decision = resolve(phase: fields.gesturePhase, proposed: proposed)
        if fields.endsGesture { latched = nil }
        return decision
    }

    /// Drops the latch. Called when the tap is re-armed after macOS disabled it.
    public mutating func reset() {
        latched = nil
    }
}
