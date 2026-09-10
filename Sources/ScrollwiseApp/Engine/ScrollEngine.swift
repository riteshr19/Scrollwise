import AppKit
import Foundation
import ScrollwiseCore

/// Owns the event tap and everything that decides whether it should be running.
///
/// Responsibilities kept here rather than in the UI, so the engine keeps working
/// with no window open and cannot be left orphaned by a view disappearing:
/// - start/stop against Accessibility permission
/// - recover after sleep, wake, and macOS disabling the tap
/// - push settings and frontmost-app changes into the tap's snapshot
@MainActor
final class ScrollEngine {

    private let snapshot: SnapshotBox
    private var tap: EventTapController?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// Surfaced to the UI so it can show a truthful state instead of guessing.
    private(set) var isRunning = false
    var onFailure: ((ScrollwiseError) -> Void)?

    init(snapshot: SnapshotBox) {
        self.snapshot = snapshot
    }

    // MARK: - Control

    /// Starts the tap if permission allows. Idempotent.
    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            Log.lifecycle.notice("Engine not started — Accessibility not granted")
            onFailure?(.accessibilityDenied)
            return
        }

        let controller = EventTapController(snapshot: snapshot) { [weak self] error in
            // Called from the tap thread; hop before touching main-actor state.
            Task { @MainActor in self?.handleTapFailure(error) }
        }
        controller.start()
        tap = controller
        isRunning = true
        observePowerNotifications()
        Log.lifecycle.info("Scroll engine started")
    }

    func stop() {
        tap?.stop()
        tap = nil
        isRunning = false
        removePowerObservers()
        Log.lifecycle.info("Scroll engine stopped")
    }

    /// Called when permission changes. Brings the engine into line either way.
    func reconcile(with status: AccessibilityStatus) {
        if status.allowsEngine {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Snapshot updates

    func apply(settings: ScrollSettings) {
        snapshot.updateSettings(settings)
    }

    func apply(frontmostBundleID: String?) {
        snapshot.updateFrontmostBundleID(frontmostBundleID)
    }

    // MARK: - Recovery

    private func handleTapFailure(_ error: ScrollwiseError) {
        switch error {
        case .eventTapDisabledByTimeout, .eventTapDisabledByUser:
            // The controller has already re-armed the tap; this is informational.
            Log.tap.notice("Recovered from: \(error.localizedDescription, privacy: .public)")
        case .eventTapCreationFailed:
            isRunning = false
            tap = nil
        default:
            break
        }
        onFailure?(error)
    }

    /// After waking, the tap is frequently found disabled. Re-arm rather than
    /// making the user restart the app.
    private func observePowerNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.lifecycle.info("Woke from sleep — verifying event tap")
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.tap?.reenableIfNeeded()
                    if self.tap == nil { self.start() }
                } else {
                    self.stop()
                }
            }
        }
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            Log.lifecycle.info("Going to sleep")
        }
    }

    private func removePowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        [sleepObserver, wakeObserver].compactMap { $0 }.forEach(center.removeObserver)
        sleepObserver = nil
        wakeObserver = nil
    }
}
