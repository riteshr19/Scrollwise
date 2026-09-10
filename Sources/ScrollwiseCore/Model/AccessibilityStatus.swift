import Foundation

/// Truthful Accessibility permission state.
///
/// The UI must never claim reversal is active when the tap cannot run, so this
/// is the only place permission is decided and every surface reads it from here.
/// The transitions are pure so they can be tested; `AccessibilityService` only
/// feeds them `AXIsProcessTrusted()` and what the engine reports.
public enum AccessibilityStatus: Equatable, Sendable {
    /// Trusted, and a tap can be created.
    case granted
    /// Not trusted. The engine cannot run.
    case denied
    /// Trusted according to the API, but the tap still would not attach. This
    /// really happens — most often after an app is replaced on disk and TCC's
    /// record no longer matches the binary.
    case grantedButTapFailed

    public var allowsEngine: Bool { self == .granted }

    /// The status after a poll of `AXIsProcessTrusted()`.
    ///
    /// A tap failure is *sticky* while trust holds. The API keeps saying
    /// "trusted" in that state, so letting a poll turn it back into `.granted`
    /// restarted the tap every second: it failed again, the UI flickered between
    /// "granted" and "not working", and each restart briefly claimed the engine
    /// was running. Only losing trust — which is what removing and re-adding the
    /// app in System Settings does — or a tap that actually attaches clears it.
    public func polled(isTrusted: Bool) -> AccessibilityStatus {
        guard isTrusted else { return .denied }
        return self == .denied ? .granted : self
    }

    /// The status after the engine failed to create its tap.
    public func afterTapFailure(isTrusted: Bool) -> AccessibilityStatus {
        isTrusted ? .grantedButTapFailed : .denied
    }

    /// The status after the engine's tap attached. Only real trust can do that.
    public func afterTapInstalled() -> AccessibilityStatus {
        .granted
    }
}
