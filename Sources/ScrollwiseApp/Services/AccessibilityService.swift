import AppKit
import ApplicationServices
import ScrollwiseCore

/// Truthful Accessibility permission state.
///
/// The UI must never claim reversal is active when the tap cannot run, so this
/// is the only place permission is decided and every surface reads it from here.
enum AccessibilityStatus: Equatable, Sendable {
    /// Trusted, and a tap can be created.
    case granted
    /// Not trusted. The engine cannot run.
    case denied
    /// Trusted according to the API, but the tap still would not attach. This
    /// really happens — most often after an app is replaced on disk and TCC's
    /// record no longer matches the binary.
    case grantedButTapFailed

    var allowsEngine: Bool { self == .granted }
}

/// Watches Accessibility trust and reports changes.
///
/// macOS posts no notification when a TCC entry is toggled, so polling is the
/// only supported way to notice. One second is frequent enough to feel immediate
/// when the user comes back from System Settings, and `AXIsProcessTrusted` is a
/// cheap local check.
@MainActor
final class AccessibilityService {

    private(set) var status: AccessibilityStatus = .denied
    private var timer: Timer?
    private var onChange: ((AccessibilityStatus) -> Void)?

    private static let pollInterval: TimeInterval = 1.0

    /// The System Settings pane that hosts the Accessibility list.
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    func start(onChange: @escaping (AccessibilityStatus) -> Void) {
        self.onChange = onChange
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
        // Keep checking while a menu is tracking, so the popover updates the
        // instant the user grants access in another window.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onChange = nil
    }

    /// Reads current trust without prompting.
    @discardableResult
    func refresh() -> AccessibilityStatus {
        let trusted = AXIsProcessTrusted()
        let newStatus: AccessibilityStatus = trusted ? .granted : .denied
        guard newStatus != status else { return status }
        status = newStatus
        Log.permission.info("Accessibility status changed to \(String(describing: newStatus), privacy: .public)")
        onChange?(newStatus)
        return newStatus
    }

    /// Records that a tap failed despite the API reporting trust, so the UI can
    /// say something more useful than "granted" while nothing works.
    func noteTapCreationFailed() {
        guard AXIsProcessTrusted() else { return }
        guard status != .grantedButTapFailed else { return }
        status = .grantedButTapFailed
        Log.permission.error("Trusted by AXIsProcessTrusted but the tap would not attach")
        onChange?(status)
    }

    /// Shows the system's own permission prompt. Only ever called from an
    /// explicit user action, never at launch behind their back.
    func requestAccess() {
        // The constant itself is a mutable global, so it is not usable from
        // Swift 6 concurrency-checked code. The key string is stable API.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }
}
