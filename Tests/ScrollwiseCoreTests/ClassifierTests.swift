import Testing
@testable import ScrollwiseCore

@Suite("Device classification")
struct DeviceClassifierTests {

    @Test("a phase-bearing continuous event is a trackpad")
    func trackpadGesture() {
        let traits = ScrollEventTraits(isContinuous: true, hasPhase: true, hasMomentumPhase: false)
        #expect(DeviceClassifier.classify(traits) == .trackpad)
    }

    @Test("inertia after the fingers lift is still the trackpad")
    func momentumIsStillTrackpad() {
        let traits = ScrollEventTraits(isContinuous: true, hasPhase: false, hasMomentumPhase: true)
        #expect(DeviceClassifier.classify(traits) == .trackpad)
    }

    @Test("a discrete phase-less click is a mouse wheel")
    func discreteWheel() {
        let traits = ScrollEventTraits(isContinuous: false, hasPhase: false, hasMomentumPhase: false)
        #expect(DeviceClassifier.classify(traits) == .mouse)
    }

    @Test("a high-resolution wheel is a mouse, not a trackpad")
    func continuousButPhaseless() {
        // Pixel-precise without phase: a high-resolution wheel. Misclassifying
        // this as a trackpad would apply the wrong rule to a real mouse.
        let traits = ScrollEventTraits(isContinuous: true, hasPhase: false, hasMomentumPhase: false)
        #expect(DeviceClassifier.classify(traits) == .mouse)
    }

    @Test("a tablet pointer is classified ahead of everything else")
    func tabletWins() {
        let traits = ScrollEventTraits(isContinuous: true, hasPhase: true,
                                       hasMomentumPhase: false, isTabletPointer: true)
        #expect(DeviceClassifier.classify(traits) == .tablet)
    }
}

@Suite("Gesture latch")
struct GestureLatchTests {

    private let reverse = AxisFlip(vertical: true, horizontal: false)

    @Test("momentum inherits the decision the gesture began with")
    func momentumFollowsGestureStart() {
        var latch = GestureLatch()
        #expect(latch.resolve(phase: .began, proposed: reverse) == reverse)
        #expect(latch.resolve(phase: .changed, proposed: .none) == reverse)
        #expect(latch.resolve(phase: .ended, proposed: .none) == reverse)
        // The setting changed mid-flick; inertia must not switch direction.
        #expect(latch.resolve(phase: .momentum, proposed: .none) == reverse)
    }

    @Test("discrete wheel clicks always use the live decision")
    func discreteIsNeverLatched() {
        var latch = GestureLatch()
        #expect(latch.resolve(phase: .discrete, proposed: reverse) == reverse)
        #expect(latch.resolve(phase: .discrete, proposed: .none) == .none)
    }

    @Test("a reset lets the next gesture pick up new settings")
    func resetClearsTheLatch() {
        var latch = GestureLatch()
        _ = latch.resolve(phase: .began, proposed: reverse)
        latch.reset()
        #expect(latch.resolve(phase: .began, proposed: .none) == .none)
    }
}
