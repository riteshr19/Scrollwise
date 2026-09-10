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
    /// Reported by tablet pucks/styluses via NSEvent subtype.
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
