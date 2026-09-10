import CoreGraphics
import ScrollwiseCore

/// Reads and writes the scroll fields of a `CGEvent`.
///
/// macOS stores the same gesture in three parallel representations per axis:
/// coarse *line* units (`DeltaAxis`), integer *pixels* (`PointDeltaAxis`), and a
/// fixed-point value (`FixedPtDeltaAxis`). Different consumers read different
/// ones — AppKit's `deltaY` comes from the first, `scrollingDeltaY` from the
/// third — so all three must be negated together or an app sees the axis
/// disagree with itself. That is the cause of the jitter and half-reversed
/// momentum that naive implementations show.
enum CGEventScrollAccess {

    // Axis 1 is vertical, axis 2 horizontal. Axis 3 is unused by every shipping
    // pointing device and is deliberately left untouched.

    static func traits(of event: CGEvent) -> ScrollEventTraits {
        ScrollEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            hasPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0,
            hasMomentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        )
    }

    /// Raw CoreGraphics phase constants. Declared here rather than imported
    /// because CoreGraphics exposes them only to C.
    private enum RawScrollPhase {
        static let began: Int64 = 1
        static let ended: Int64 = 4
        static let cancelled: Int64 = 8
    }

    private enum RawMomentumPhase {
        static let ended: Int64 = 3
    }

    static func phase(of event: CGEvent) -> GesturePhase {
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if momentum != 0 {
            return .momentum
        }
        let scroll = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        switch scroll {
        case 0: return .discrete
        case RawScrollPhase.began: return .began
        case RawScrollPhase.ended, RawScrollPhase.cancelled: return .ended
        default: return .changed
        }
    }

    /// True once inertia has finished, so the gesture latch can be released.
    static func isGestureFinished(_ event: CGEvent) -> Bool {
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if momentum == RawMomentumPhase.ended { return true }
        if momentum != 0 { return false }
        let scroll = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        return scroll == RawScrollPhase.ended || scroll == RawScrollPhase.cancelled
    }

    /// Negates every representation of the requested axes in place on the event.
    ///
    /// Only the six scroll delta fields are touched. Modifier flags, timestamps,
    /// location, phase, source state and the tablet fields are left exactly as
    /// they arrived, so nothing but scrolling direction is affected.
    static func apply(_ flip: AxisFlip, to event: CGEvent) {
        if flip.vertical {
            negate(event, line: .scrollWheelEventDeltaAxis1,
                   point: .scrollWheelEventPointDeltaAxis1,
                   fixed: .scrollWheelEventFixedPtDeltaAxis1)
        }
        if flip.horizontal {
            negate(event, line: .scrollWheelEventDeltaAxis2,
                   point: .scrollWheelEventPointDeltaAxis2,
                   fixed: .scrollWheelEventFixedPtDeltaAxis2)
        }
    }

    private static func negate(
        _ event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixed: CGEventField
    ) {
        event.setIntegerValueField(line, value: -event.getIntegerValueField(line))
        event.setIntegerValueField(point, value: -event.getIntegerValueField(point))
        event.setDoubleValueField(fixed, value: -event.getDoubleValueField(fixed))
    }

    /// Used by diagnostics and tests to observe an event as a value type.
    static func delta(of event: CGEvent) -> ScrollDelta {
        ScrollDelta(
            vertical: AxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            ),
            horizontal: AxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            )
        )
    }
}
