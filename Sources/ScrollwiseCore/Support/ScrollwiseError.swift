import Foundation

public enum ScrollwiseError: LocalizedError, Equatable {
    case accessibilityDenied
    case eventTapCreationFailed
    case eventTapDisabledByTimeout
    case eventTapDisabledByUser
    case launchAtLoginFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "Scrollwise needs Accessibility access to read scroll events."
        case .eventTapCreationFailed:
            "Scrollwise could not attach to the system event stream."
        case .eventTapDisabledByTimeout:
            "macOS switched the event tap off because it stopped responding."
        case .eventTapDisabledByUser:
            "The event tap was switched off."
        case .launchAtLoginFailed(let reason):
            "Could not change the login item: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .accessibilityDenied:
            "Open Privacy & Security › Accessibility and switch Scrollwise on."
        case .eventTapCreationFailed, .eventTapDisabledByTimeout, .eventTapDisabledByUser:
            "Scrollwise will try to reconnect on its own."
        case .launchAtLoginFailed:
            "Open Login Items in System Settings to change it there."
        }
    }
}
