import CoreGraphics
import Foundation
import ScrollwiseCore

/// Owns one `CGEventTap`, its dedicated thread, and its in-place recovery.
///
/// ## Why a dedicated thread
/// The tap callback runs on whichever run loop the source is attached to. On the
/// main run loop, any slow UI work — a SwiftUI re-render, a menu tracking loop,
/// a window resize — sits directly in the path of every scroll event, and macOS
/// responds by disabling a tap it considers unresponsive. Giving the tap its own
/// thread and run loop keeps the two entirely independent.
///
/// ## One controller, one tap, once
/// A controller starts at most once and cannot be restarted; `ScrollEngine`
/// makes a new one each time. `stop()` is effective at any moment — before the
/// thread has created the tap, while it is creating it, or while it runs — and
/// returns only once the thread has removed the tap and exited. Together those
/// make "two taps at once" unreachable: an earlier version returned from `stop()`
/// without effect if the thread had not yet published its run loop, and that
/// thread then installed a tap nothing could remove. A second start left two
/// taps flipping every event twice.
///
/// ## Threads
/// - `tap` and `latch`: the tap thread only. `reenableIfNeeded()` hops there.
/// - `hasStarted`, `isCancelled`, `runLoop`: under `lock`, from either thread.
/// - `snapshot`: `SnapshotBox`, the lock-protected value the main thread writes.
///
/// ## What the callback is allowed to do
/// Take one uncontended lock, read a handful of integers, negate some of them,
/// return. No allocation, no logging, no Objective-C messaging into AppKit, no
/// disk, no `await`. Everything it needs is pre-computed in `SnapshotBox`.
public final class EventTapController: @unchecked Sendable {

    /// What the tap reports about itself, delivered on the tap thread.
    public enum Event: Equatable, Sendable {
        /// The tap exists and is enabled: events are now being modified.
        case installed
        /// `CGEvent.tapCreate` refused — almost always missing or stale trust.
        case creationFailed
        /// macOS told the callback it switched the tap off; it has already been
        /// re-enabled in place.
        case disabledByTimeout
        case disabledByUserInput
        /// The watchdog found the tap switched off without any notification
        /// having arrived, and re-enabled it.
        case reenabled
    }

    public typealias EventHandler = @Sendable (EventTapController, Event) -> Void

    private let snapshot: SnapshotBox
    private let onEvent: EventHandler

    // Tap thread only.
    private var tap: CFMachPort?
    private var latch = GestureLatch()

    // Guarded by `lock`.
    private let lock = NSLock()
    private var hasStarted = false
    private var isCancelled = false
    private var runLoop: CFRunLoop?

    /// Signalled once when the tap thread exits, whichever way it exits.
    private let exited = DispatchSemaphore(value: 0)

    /// The callback never blocks, so the thread exits within microseconds of
    /// being asked; this bound only exists so a bug cannot hang the main thread.
    private static let stopTimeout: DispatchTimeInterval = .seconds(2)

    /// How often the tap thread checks that macOS has not switched the tap off.
    ///
    /// The documented recovery — re-enabling when the callback receives
    /// `tapDisabledByTimeout` — is not enough on its own. Measured on macOS 26.5:
    /// after the callback stalled past the timeout, the window server disabled
    /// the tap and no notification ever reached the callback, so scrolling
    /// silently stopped being reversed while every surface still read
    /// "Running". The watchdog closes that gap. The tolerance lets the system
    /// coalesce the wake-up with others, so it costs close to nothing at idle.
    private static let watchdogInterval: CFTimeInterval = 1.0
    private static let watchdogTolerance: CFTimeInterval = 0.5

    #if SCROLLWISE_INSTRUMENT
    public let instrument = EventTapInstrument()
    #endif

    public init(snapshot: SnapshotBox, onEvent: @escaping EventHandler) {
        self.snapshot = snapshot
        self.onEvent = onEvent
    }

    // MARK: - Lifecycle

    /// True while the tap is attached and not being stopped.
    public var isRunning: Bool {
        lock.withLock { runLoop != nil && !isCancelled }
    }

    /// Starts the tap thread. Has no effect if already started or stopped.
    public func start() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !hasStarted, !isCancelled else { return false }
            hasStarted = true
            return true
        }
        guard shouldStart else { return }

        // The thread holds the controller strongly until it exits. That is what
        // keeps the unretained `userInfo` pointer valid: the tap is invalidated
        // before `threadMain` returns, so no callback can outlive the controller.
        let thread = Thread { self.threadMain() }
        thread.name = "engineer.riteshrana.scrollwise.eventtap"
        // Input handling should not lose to background work, but it is not
        // real-time either; userInteractive is the correct band.
        thread.qualityOfService = .userInteractive
        thread.start()
        Log.tap.info("Event tap thread starting")
    }

    /// Removes the tap and waits for its thread to exit. Safe at any moment and
    /// safe to call repeatedly.
    public func stop() {
        let (loop, started) = lock.withLock { () -> (CFRunLoop?, Bool) in
            guard !isCancelled else { return (nil, false) }
            isCancelled = true
            return (runLoop, hasStarted)
        }
        // No run loop yet means the thread has not reached the point of running
        // it, and will see `isCancelled` under the lock before it does.
        if let loop { Self.stopWhenRunning(loop) }
        guard started else { return }
        if exited.wait(timeout: .now() + Self.stopTimeout) == .timedOut {
            Log.tap.error("Event tap thread did not exit within the stop timeout")
        }
    }

    /// Re-arms a tap macOS switched off, on the tap's own thread — the only one
    /// that touches `tap`. Safe to call repeatedly and from any thread. The
    /// watchdog does the same on its own; this is for wake, when waiting up to
    /// a second is needless.
    public func reenableIfNeeded() {
        guard let loop = lock.withLock({ isCancelled ? nil : runLoop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            reenableIfDisabled()
        }
        CFRunLoopWakeUp(loop)
    }

    /// Tap thread only.
    private func reenableIfDisabled() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        // Whatever gesture was in flight passed through untouched while the tap
        // was off; its latch describes nothing any more.
        latch.reset()
        onEvent(self, .reenabled)
    }

    /// Queued rather than calling `CFRunLoopStop` directly: stopping a loop that
    /// has not yet entered its run is a no-op, so a stop racing the start would
    /// be lost. A queued block runs as soon as the loop does.
    private static func stopWhenRunning(_ loop: CFRunLoop) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
    }

    // MARK: - Tap thread

    private func threadMain() {
        defer { exited.signal() }

        guard let tap = makeTap() else {
            if !lock.withLock({ isCancelled }) { onEvent(self, .creationFailed) }
            Log.tap.error("Event tap could not be created")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            if !lock.withLock({ isCancelled }) { onEvent(self, .creationFailed) }
            return
        }
        self.tap = tap

        let loop: CFRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let watchdog = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + Self.watchdogInterval,
            Self.watchdogInterval, 0, 0
        ) { [self] _ in
            reenableIfDisabled()
        }
        if let watchdog {
            CFRunLoopTimerSetTolerance(watchdog, Self.watchdogTolerance)
            CFRunLoopAddTimer(loop, watchdog, .commonModes)
        }

        // Publishing the run loop and checking for a stop happen under one lock,
        // so a concurrent `stop()` either sees the loop and queues a stop on it,
        // or has already set `isCancelled` and this thread never runs.
        let shouldRun = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            runLoop = loop
            return true
        }

        if shouldRun {
            Log.tap.info("Event tap installed and enabled")
            onEvent(self, .installed)
            while !lock.withLock({ isCancelled }) {
                _ = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
            }
        }

        if let watchdog { CFRunLoopTimerInvalidate(watchdog) }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        lock.withLock { runLoop = nil }
        self.tap = nil
        Log.tap.info("Event tap removed")
    }

    private func makeTap() -> CFMachPort? {
        // Scroll wheel events only. Narrowing the mask means the callback is
        // never even consulted for clicks, keys, drags or cursor movement, which
        // is both faster and the strongest possible guarantee that Scrollwise
        // cannot affect unrelated input.
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
        // macOS switches a tap off if it ever believes the callback stalled.
        // That arrives here as an event type, not an error. Re-enabling from the
        // callback is the documented recovery and safe here: this is the tap's
        // own thread. The report is informational — nothing needs restarting.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            latch.reset()
            onEvent(self, type == .tapDisabledByTimeout ? .disabledByTimeout : .disabledByUserInput)
            return nil
        }

        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        #if SCROLLWISE_INSTRUMENT
        let started = EventTapInstrument.now()
        instrument.consumeStall()
        defer { instrument.record(since: started) }
        #endif

        let current = snapshot.read()
        let fields = CGEventScrollAccess.rawFields(of: event)

        // Decided even while the master switch is off — the transformer then
        // proposes no flip — so a gesture already in flight finishes the way it
        // started, exactly as for any other setting change. The next gesture,
        // and every wheel click, sees the switch at once.
        let proposed = ScrollTransformer.flip(
            device: DeviceClassifier.classify(fields.traits),
            frontmostBundleID: current.frontmostBundleID,
            settings: current.settings
        )

        // Hold one gesture's decision steady from first touch through last
        // inertial event, so a mid-flick settings change cannot reverse the
        // momentum of a gesture that already started.
        let resolved = latch.resolve(fields, proposed: proposed)

        if !resolved.isIdentity {
            CGEventScrollAccess.apply(resolved, to: event)
        }
        return Unmanaged.passUnretained(event)
    }
}

/// Free function so it can be used as a C function pointer. Recovers the
/// controller from `userInfo` without retaining it — the tap thread owns the
/// controller for as long as the tap exists.
private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
