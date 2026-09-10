import AppKit

/// Tracks which app is frontmost so per-app rules can be applied without the
/// event callback ever calling into `NSWorkspace`.
///
/// `NSWorkspace.frontmostApplication` is a main-thread, cross-process query. In
/// the hot path it would be both slow and a deadlock risk, so the value is
/// cached here and pushed into `SnapshotBox` on every activation.
@MainActor
final class FrontmostAppMonitor {

    private var observer: NSObjectProtocol?
    private let onChange: (String?) -> Void

    init(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        onChange(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.onChange(app?.bundleIdentifier) }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
