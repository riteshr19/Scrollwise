import Foundation

/// Holds one gesture's flip decision steady from first touch through the last
/// momentum event.
///
/// Without this, changing a setting (or switching app) mid-flick would reverse the
/// inertia but not the fingers that launched it, so the content would visibly snap
/// direction while decelerating. Latching is what makes momentum feel correct.
///
/// Not thread-safe by design: it is touched only from the event tap's run loop.
public struct GestureLatch {
    private var latched: AxisFlip?

    public init() {}

    /// Returns the decision to use for this event, updating the latch as the
    /// gesture progresses.
    public mutating func resolve(phase: GesturePhase, proposed: AxisFlip) -> AxisFlip {
        switch phase {
        case .discrete:
            // Wheel clicks are independent; always use the live decision.
            latched = nil
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
            let result = latched ?? proposed
            // Keep the latch: momentum events arrive *after* .ended and must match.
            return result
        }
    }

    /// Drops the latch. Called when momentum finishes or the tap is re-armed.
    public mutating func reset() {
        latched = nil
    }
}
