import CoreGraphics
import Foundation
import ScrollwiseCore

/// Owns the `CGEventTap`, its dedicated thread, and its recovery behaviour.
///
/// ## Why a dedicated thread
/// The tap callback runs on whichever run loop the source is attached to. On the
/// main run loop, any slow UI work — a SwiftUI re-render, a menu tracking loop,
/// a window resize — sits directly in the path of every scroll event, and macOS
/// responds by disabling a tap it considers unresponsive. Giving the tap its own
/// thread and run loop keeps the two entirely independent.
///
/// ## What the callback is allowed to do
/// Take one uncontended lock, read six integers, negate some of them, return.
/// No allocation, no logging, no Objective-C messaging into AppKit, no disk,
/// no `await`. Everything it needs is pre-computed in `SnapshotBox`.
final class EventTapController: @unchecked Sendable {

    /// Reported when macOS switches the tap off, or it could not be created.
    typealias FailureHandler = @Sendable (ScrollwiseError) -> Void

    private let snapshot: SnapshotBox
    private let onFailure: FailureHandler

    // Touched only on the tap thread after start().
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var latch = GestureLatch()

    // Written on the tap thread, read on the main thread to stop it.
    private let tapRunLoopLock = NSLock()
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    init(snapshot: SnapshotBox, onFailure: @escaping FailureHandler) {
        self.snapshot = snapshot
        self.onFailure = onFailure
    }

    // MARK: - Lifecycle

    var isRunning: Bool {
        tapRunLoopLock.lock()
        defer { tapRunLoopLock.unlock() }
        return tapRunLoop != nil
    }

    func start() {
        guard !isRunning else { return }
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "engineer.riteshrana.scrollwise.eventtap"
        // Input handling should not lose to background work, but it is not
        // real-time either; userInteractive is the correct band.
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        Log.tap.info("Event tap thread starting")
    }

    func stop() {
        tapRunLoopLock.lock()
        let loop = tapRunLoop
        tapRunLoop = nil
        tapRunLoopLock.unlock()

        guard let loop else { return }
        CFRunLoopStop(loop)
        thread = nil
        Log.tap.info("Event tap stopped")
    }

    /// Re-arms a tap macOS switched off. Safe to call repeatedly.
    func reenableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.tap.notice("Re-enabled a disabled event tap")
    }

    // MARK: - Tap thread

    private func threadMain() {
        guard let tap = makeTap() else {
            onFailure(.eventTapCreationFailed)
            return
        }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        let loop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        tapRunLoopLock.lock()
        tapRunLoop = loop
        tapRunLoopLock.unlock()

        Log.tap.info("Event tap installed and enabled")
        CFRunLoopRun()

        // Unwound by stop().
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    private func makeTap() -> CFMachPort? {
        // Scroll wheel events only. Narrowing the mask means the callback is
        // never even consulted for clicks, keys, drags or cursor movement, which
        // is both faster and the strongest possible guarantee that Scroll
        // Reverser cannot affect unrelated input.
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,        // this login session
            place: .headInsertEventTap,     // before other taps, so we see raw values
            options: .defaultTap,           // we modify events, so not listenOnly
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Hot path

    /// Called once per scroll event on the tap thread. Keep it small.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a tap off if it ever believes the callback stalled, and
        // after waking from sleep. Both arrive here as event types, not errors.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            latch.reset()
            onFailure(type == .tapDisabledByTimeout
                      ? .eventTapDisabledByTimeout
                      : .eventTapDisabledByUser)
            return nil
        }

        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let current = snapshot.read()

        // Cheapest possible exit when the app is switched off.
        guard current.settings.isEnabled else { return Unmanaged.passUnretained(event) }

        let device = DeviceClassifier.classify(CGEventScrollAccess.traits(of: event))
        let proposed = ScrollTransformer.flip(
            device: device,
            frontmostBundleID: current.frontmostBundleID,
            settings: current.settings
        )

        // Hold one gesture's decision steady from first touch through last
        // inertial event, so a mid-flick settings change cannot reverse the
        // momentum of a gesture that already started.
        let resolved = latch.resolve(phase: CGEventScrollAccess.phase(of: event), proposed: proposed)

        if CGEventScrollAccess.isGestureFinished(event) {
            latch.reset()
        }

        guard !resolved.isIdentity else { return Unmanaged.passUnretained(event) }

        CGEventScrollAccess.apply(resolved, to: event)
        return Unmanaged.passUnretained(event)
    }
}

/// Free function so it can be used as a C function pointer. Recovers the
/// controller from `userInfo` without retaining it — the controller outlives the
/// tap because `ScrollEngine` owns both.
private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
