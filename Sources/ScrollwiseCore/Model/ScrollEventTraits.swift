import Foundation

/// The observable facts about a scroll event, lifted out of `CGEvent` so the
/// classifier and transformer can be tested without synthesising real input.
public struct ScrollEventTraits: Equatable, Sendable {
    /// `kCGScrollWheelEventIsContinuous` — set by pixel-precise devices.
    public let isContinuous: Bool
    /// The event carries a gesture phase (began/changed/ended). Trackpads do; wheels do not.
    public let hasPhase: Bool
    /// The event is part of post-gesture inertial scrolling.
    public let hasMomentumPhase: Bool
    /// The event's mouse subtype marks it as coming from a tablet pointer.
    public let isTabletPointer: Bool

    public init(
        isContinuous: Bool,
        hasPhase: Bool,
        hasMomentumPhase: Bool,
        isTabletPointer: Bool = false
    ) {
        self.isContinuous = isContinuous
        self.hasPhase = hasPhase
        self.hasMomentumPhase = hasMomentumPhase
        self.isTabletPointer = isTabletPointer
    }
}

/// Where an event sits in a gesture's life. Drives the momentum latch.
public enum GesturePhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case momentum
    /// A discrete wheel click — no gesture around it.
    case discrete
}

/// The four raw integers the event tap reads off a scroll event.
///
/// CoreGraphics publishes the phase and subtype constants to C only, so the
/// adapter reads plain integers and every decision about what they *mean* is
/// made here, where it is tested. That mapping used to live, untested, in the
/// adapter — and it carried a real bug: it treated scroll-phase *ended* as the
/// end of the gesture, which released the momentum latch just before the
/// inertia that follows it arrived. A setting changed mid-flick then reversed
/// the momentum, which is precisely what the latch exists to prevent.
public struct RawScrollFields: Equatable, Sendable {
    /// `kCGScrollWheelEventIsContinuous`.
    public let isContinuous: Int64
    /// `kCGScrollWheelEventScrollPhase`, a `CGScrollPhase`.
    public let scrollPhase: Int64
    /// `kCGScrollWheelEventMomentumPhase`, a `CGMomentumScrollPhase`.
    public let momentumPhase: Int64
    /// `kCGMouseEventSubtype`, a `CGEventMouseSubtype`.
    public let mouseSubtype: Int64

    public init(
        isContinuous: Int64 = 0,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        mouseSubtype: Int64 = 0
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.mouseSubtype = mouseSubtype
    }

    /// `CGScrollPhase` values.
    public enum ScrollPhase {
        public static let began: Int64 = 1
        public static let changed: Int64 = 2
        public static let ended: Int64 = 4
        public static let cancelled: Int64 = 8
        public static let mayBegin: Int64 = 128
    }

    /// `CGMomentumScrollPhase` values.
    public enum MomentumPhase {
        public static let begin: Int64 = 1
        public static let continuing: Int64 = 2
        public static let end: Int64 = 3
    }

    /// `CGEventMouseSubtype` values. Only the two tablet subtypes matter here.
    public enum MouseSubtype {
        public static let tabletPoint: Int64 = 1
        public static let tabletProximity: Int64 = 2
    }

    public var traits: ScrollEventTraits {
        ScrollEventTraits(
            isContinuous: isContinuous != 0,
            hasPhase: scrollPhase != 0,
            hasMomentumPhase: momentumPhase != 0,
            isTabletPointer: mouseSubtype == MouseSubtype.tabletPoint
                || mouseSubtype == MouseSubtype.tabletProximity
        )
    }

    public var gesturePhase: GesturePhase {
        if momentumPhase != 0 { return .momentum }
        switch scrollPhase {
        case 0: return .discrete
        // A touch that may become a scroll is where the gesture starts.
        case ScrollPhase.began, ScrollPhase.mayBegin: return .began
        case ScrollPhase.ended, ScrollPhase.cancelled: return .ended
        default: return .changed
        }
    }

    /// True only for the last event a gesture can produce, so the latch may be
    /// released. Scroll-phase *ended* is deliberately not one of them: the
    /// fingers have lifted, but the momentum phase that follows belongs to the
    /// same gesture. A gesture that ends with no momentum simply leaves the latch
    /// held until the next `.began` overwrites it, which is harmless.
    public var endsGesture: Bool {
        if momentumPhase == MomentumPhase.end { return true }
        return momentumPhase == 0 && scrollPhase == ScrollPhase.cancelled
    }
}
