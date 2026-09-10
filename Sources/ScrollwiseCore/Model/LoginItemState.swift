import Foundation

/// What `SMAppService` reports about the app's login item, reduced to the three
/// questions the UI actually asks.
///
/// ## The trap this type exists to prevent
/// `SMAppService.mainApp.status` returns **`.notFound`** for an app that has
/// simply never been registered — not `.notRegistered`. `register()` from that
/// state succeeds and the status becomes `.enabled`.
///
/// So `.notFound` is *not* evidence that macOS refuses a login item. Treating it
/// as "unavailable" disables the switch on every fresh install and makes the
/// feature impossible to turn on: the only way out of `.notFound` is to
/// register, and a disabled switch can never do that. Only a thrown error from
/// `register()` is evidence of a real refusal.
public enum LoginItemState: Sendable, Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    /// Never registered. Offerable, not refused.
    case neverRegistered

    /// Raw values of `SMAppService.Status`, which is an `Int`-backed enum:
    /// 0 notRegistered, 1 enabled, 2 requiresApproval, 3 notFound.
    public init(rawStatus: Int) {
        switch rawStatus {
        case 1: self = .enabled
        case 2: self = .requiresApproval
        case 3: self = .neverRegistered
        default: self = .notRegistered
        }
    }

    /// `.requiresApproval` counts as on: the registration exists, the user has
    /// simply not confirmed it. Reporting it as off makes the switch snap back
    /// and hides the fact that there is something to approve.
    public var isEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }

    public var needsApproval: Bool {
        self == .requiresApproval
    }
}
