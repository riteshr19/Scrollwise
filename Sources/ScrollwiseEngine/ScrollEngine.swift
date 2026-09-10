import AppKit
import ApplicationServices
import Foundation
import ScrollwiseCore

/// Owns the event tap and everything that decides whether it should be running.
///
/// Responsibilities kept here rather than in the UI, so the engine keeps working
/// with no window open and cannot be left orphaned by a view disappearing:
/// - start/stop against Accessibility permission
/// - recover after wake, a failed creation, and macOS disabling the tap
/// - push settings and frontmost-app changes into the tap's snapshot
///
/// `state` is what the engine is actually doing, reported only from what the tap
/// thread observed. It never says `.running` because a start was requested.
@MainActor
public final class ScrollEngine {

    public enum State: Equatable, Sendable {
        /// No tap, by request or because permission is missing.
        case stopped
        /// A tap was requested and has not attached yet. Not running: nothing
        /// is being reversed until the tap says it is installed.
        case starting
        /// The tap is attached and modifying events.
        case running
        /// Tap creation failed although the process is trusted. Retried after
        /// `retryDelay` and on wake; see `AccessibilityStatus.grantedButTapFailed`.
        case failed
    }

    public private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    public var isRunning: Bool { state == .running }
    public var onStateChange: ((State) -> Void)?

    /// How long a failed tap waits before trying again. Long enough that a
    /// grant that is genuinely stale costs almost nothing; short enough that a
    /// transient refusal — the window server not yet ready at login, say —
    /// recovers without the user doing anything.
    public static let retryDelay: Duration = .seconds(30)

    private let snapshot: SnapshotBox
    private let isTrusted: () -> Bool
    private var tap: EventTapController?
    private var wakeObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?

    /// `isTrusted` is injectable so the live checks can drive the engine; the
    /// app uses the real `AXIsProcessTrusted`.
    public init(snapshot: SnapshotBox, isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.snapshot = snapshot
        self.isTrusted = isTrusted
    }

    // MARK: - Control

    /// Starts a tap if permission allows. Idempotent: while one is starting or
    /// running, this does nothing.
    public func start() {
        guard state == .stopped || state == .failed else { return }
        guard isTrusted() else {
            Log.lifecycle.notice("Engine not started — Accessibility not granted")
            return
        }
        retryTask?.cancel()
        retryTask = nil

        let controller = EventTapController(snapshot: snapshot) { [weak self] controller, event in
            // Called on the tap thread; hop before touching main-actor state,
            // carrying the reporter's identity so a stale report can be ignored.
            let reporter = ObjectIdentifier(controller)
            Task { @MainActor in self?.handle(event, from: reporter) }
        }
        tap = controller
        state = .starting
        observeWake()
        controller.start()
    }

    /// Removes the tap. Returns only once the tap thread has exited, so no tap
    /// outlives this call and a following `start()` can never overlap it.
    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        tap?.stop()
        tap = nil
        removeWakeObserver()
        if state != .stopped {
            Log.lifecycle.info("Scroll engine stopped")
        }
        state = .stopped
    }

    /// Called when permission changes. Brings the engine into line.
    public func reconcile(with status: AccessibilityStatus) {
        switch status {
        case .granted: start()
        case .denied: stop()
        // The engine's own retry owns this state; stopping would cancel it.
        case .grantedButTapFailed: break
        }
    }

    /// After waking, the tap is sometimes found disabled. Re-arm it, or retry a
    /// failed one, rather than making the user restart the app.
    public func handleWake() {
        switch state {
        case .running: tap?.reenableIfNeeded()
        case .failed: start()
        case .stopped, .starting: break
        }
    }

    // MARK: - Snapshot updates

    public func apply(settings: ScrollSettings) {
        snapshot.updateSettings(settings)
    }

    public func apply(frontmostBundleID: String?) {
        snapshot.updateFrontmostBundleID(frontmostBundleID)
    }

    // MARK: - Reports from the tap thread

    private func handle(_ event: EventTapController.Event, from reporter: ObjectIdentifier) {
        // A controller that has since been stopped or replaced reports into the
        // void. Acting on it once let a late failure from an old tap mark the
        // engine stopped while the current tap ran on, unowned and unstoppable.
        guard let tap, ObjectIdentifier(tap) == reporter else { return }

        switch event {
        case .installed:
            state = .running
            Log.lifecycle.info("Scroll engine running")
        case .creationFailed:
            // The thread has already exited; nothing is attached.
            self.tap = nil
            state = .failed
            scheduleRetry()
        case .disabledByTimeout, .disabledByUserInput, .reenabled:
            Log.tap.notice("macOS disabled the event tap (\(String(describing: event), privacy: .public)); re-enabled in place")
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled, let self, self.state == .failed else { return }
            Log.lifecycle.info("Retrying the event tap")
            self.start()
        }
    }

    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.lifecycle.info("Woke from sleep — verifying event tap")
                self?.handleWake()
            }
        }
    }

    private func removeWakeObserver() {
        guard let wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }
}
