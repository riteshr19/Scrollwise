import Foundation

/// Failures a service reports to the UI. Event-tap and permission problems are
/// not here: they are states, not errors, and live in `AccessibilityStatus` and
/// `ScrollEngine.State`, which every surface reads directly.
public enum ScrollwiseError: LocalizedError, Equatable {
    case launchAtLoginFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchAtLoginFailed(let reason):
            "Could not change the login item: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .launchAtLoginFailed:
            "Open Login Items in System Settings to change it there."
        }
    }
}
