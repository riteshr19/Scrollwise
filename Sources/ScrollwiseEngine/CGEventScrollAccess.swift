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
///
/// This type only moves integers in and out of the event. What they mean —
/// device class, gesture phase, when a gesture ends — is decided in Core by
/// `RawScrollFields`, where it is tested.
public enum CGEventScrollAccess {

    // Axis 1 is vertical, axis 2 horizontal. Axis 3 and the accelerated-delta
    // fields are deliberately left untouched: no shipping pointing device drives
    // axis 3, and the accelerated fields are not read by AppKit's scroll deltas.

    /// The four integers classification and latching need. Four field reads,
    /// no allocation.
    public static func rawFields(of event: CGEvent) -> RawScrollFields {
        RawScrollFields(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            mouseSubtype: event.getIntegerValueField(.mouseEventSubtype)
        )
    }

    /// Negates every representation of the requested axes in place on the event.
    ///
    /// Only the six scroll delta fields are touched. Modifier flags, timestamps,
    /// location, phase, source state and the tablet fields are left exactly as
    /// they arrived, so nothing but scrolling direction is affected.
    public static func apply(_ flip: AxisFlip, to event: CGEvent) {
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

    /// Reads all three representations *before* writing any of them.
    ///
    /// Writing the line field makes CoreGraphics recompute the pixel and
    /// fixed-point fields from it. An earlier version read each field just
    /// before negating it, so it read those recomputed values — already
    /// negative, and rescaled — and flipped them back. Measured on the live tap:
    /// `line 3 · point 30 · fixed 3.0` arrived as `line −3 · point +24 ·
    /// fixed +3.0`, so every app reading precise deltas (`scrollingDeltaY`) saw
    /// the original direction. The negation itself is `AxisDelta.negated` from
    /// Core: tested, and unable to trap on `Int64.min`.
    private static func negate(
        _ event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixed: CGEventField
    ) {
        let flipped = AxisDelta(
            line: event.getIntegerValueField(line),
            point: event.getIntegerValueField(point),
            fixedPoint: event.getDoubleValueField(fixed)
        ).negated
        event.setIntegerValueField(line, value: flipped.line)
        event.setIntegerValueField(point, value: flipped.point)
        event.setDoubleValueField(fixed, value: flipped.fixedPoint)
    }

    /// Used by diagnostics and tests to observe an event as a value type.
    public static func delta(of event: CGEvent) -> ScrollDelta {
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
