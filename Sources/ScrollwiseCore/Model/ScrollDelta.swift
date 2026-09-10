import Foundation

/// One scroll axis, in all three representations macOS carries simultaneously.
///
/// A `CGEvent` scroll wheel event stores the same physical gesture three ways:
/// coarse line units, integer pixels, and a fixed-point value. They must be
/// flipped **together**. Flipping only one produces the jitter and half-reversed
/// momentum that naive implementations exhibit.
public struct AxisDelta: Equatable, Sendable {
    public var line: Int64
    public var point: Int64
    public var fixedPoint: Double

    public init(line: Int64 = 0, point: Int64 = 0, fixedPoint: Double = 0) {
        self.line = line
        self.point = point
        self.fixedPoint = fixedPoint
    }

    /// Returns a new value with every representation negated. Never mutates.
    public var negated: AxisDelta {
        AxisDelta(line: Self.negate(line), point: Self.negate(point), fixedPoint: -fixedPoint)
    }

    /// Integer negation that cannot trap. Plain `-` traps on `Int64.min`, and
    /// this runs inside the event tap on values any process can post, so one
    /// crafted event would otherwise take the app down. `Int64.min` is left as
    /// it is — it has no positive counterpart — and every other value negates
    /// exactly, so flipping twice is still the identity.
    public static func negate(_ value: Int64) -> Int64 {
        0 &- value
    }

    public var isZero: Bool { line == 0 && point == 0 && fixedPoint == 0 }
}

/// A complete scroll event's movement, both axes.
public struct ScrollDelta: Equatable, Sendable {
    public var vertical: AxisDelta
    public var horizontal: AxisDelta

    public init(vertical: AxisDelta = .init(), horizontal: AxisDelta = .init()) {
        self.vertical = vertical
        self.horizontal = horizontal
    }

    /// Applies a flip decision, returning a new value. Pure.
    public func applying(_ flip: AxisFlip) -> ScrollDelta {
        ScrollDelta(
            vertical: flip.vertical ? vertical.negated : vertical,
            horizontal: flip.horizontal ? horizontal.negated : horizontal
        )
    }
}

/// Which axes to invert for one event. The entire output of the decision layer.
public struct AxisFlip: Equatable, Sendable {
    public var vertical: Bool
    public var horizontal: Bool

    public init(vertical: Bool, horizontal: Bool) {
        self.vertical = vertical
        self.horizontal = horizontal
    }

    public static let none = AxisFlip(vertical: false, horizontal: false)
    public var isIdentity: Bool { !vertical && !horizontal }
}
