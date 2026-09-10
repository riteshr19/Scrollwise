import Foundation
import ServiceManagement
import ScrollwiseCore

/// Login item registration through `SMAppService`, the supported API since
/// macOS 13. The old `LSSharedFileList` and login-item helper-bundle approaches
/// are deprecated and are deliberately not used.
@MainActor
enum LaunchAtLoginService {

    /// What the system actually reports, which is not always what the user last
    /// asked for — they can revoke it in System Settings › Login Items.
    ///
    /// `.requiresApproval` counts as on: the registration exists, the user has
    /// simply not confirmed it yet. Reporting it as off would make the switch
    /// snap back and hide the fact that there is something to approve.
    static var isEnabled: Bool { state.isEnabled }

    /// Registered, but macOS is waiting for the user to confirm it in
    /// System Settings › General › Login Items.
    static var needsApproval: Bool { state.needsApproval }

    /// The system's own report, reduced to the three questions the UI asks.
    /// The mapping — including why `.notFound` is offerable rather than a
    /// refusal — lives in `LoginItemState`, where it is tested.
    static var state: LoginItemState {
        LoginItemState(rawStatus: SMAppService.mainApp.status.rawValue)
    }

    /// Why the system last refused to register, or `nil` if it has not refused.
    ///
    /// This deliberately does *not* come from `status`. A main app that has
    /// simply never been registered reports `.notFound`, not `.notRegistered`,
    /// so treating `.notFound` as "macOS will not accept a login item" disables
    /// the control forever: the only way out of `.notFound` is to register, and
    /// a disabled switch can never do that. Only a thrown error is evidence of
    /// an actual refusal.
    private(set) static var refusalReason: String?

    /// False only after the system has genuinely rejected a registration.
    static var isAvailable: Bool { refusalReason == nil }

    /// Returns the state actually achieved, which the caller should write back
    /// into settings so the UI never disagrees with the system.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Bool, ScrollwiseError> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refusalReason = nil
            Log.login.info("Login item set to \(enabled); status now \(statusDescription, privacy: .public)")
            return .success(isEnabled)
        } catch {
            refusalReason = error.localizedDescription
            Log.login.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.launchAtLoginFailed(error.localizedDescription))
        }
    }

    /// Opens System Settings › General › Login Items, where a registration
    /// waiting for approval is confirmed.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Human-readable form of what `SMAppService` reports, so a refusal can be
    /// diagnosed from the log instead of guessed at.
    static var statusDescription: String {
        switch state {
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notRegistered: "notRegistered"
        case .neverRegistered: "notFound (never registered)"
        }
    }
}
