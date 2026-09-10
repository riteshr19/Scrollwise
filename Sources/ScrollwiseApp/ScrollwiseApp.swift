import AppKit
import SwiftUI
import ScrollwiseCore

/// Application entry point.
///
/// `MenuBarExtra` with the `.window` style is what makes mockup 1d native: macOS
/// draws the popover on its own Liquid Glass material, sampling the real desktop
/// behind the menu bar. There is no `Window` scene for settings — that window is
/// created on demand by `SettingsWindowPresenter`, because an `LSUIElement` app
/// should not keep a restorable window scene alive when it has no Dock icon.
@main
struct ScrollwiseApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.state)
        } label: {
            // A template image so macOS tints it correctly for the menu bar's
            // appearance, including over a light wallpaper in dark mode.
            Image(systemName: delegate.state.isActive
                  ? "arrow.up.arrow.down.circle.fill"
                  : "arrow.up.arrow.down.circle")
                .accessibilityLabel(menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }

    /// Spoken by VoiceOver for the menu bar icon; held to the same standard as
    /// the popover's headline.
    private var menuBarLabel: String {
        if delegate.state.isReversingSomething { return "Scrollwise, reversing" }
        return delegate.state.isActive ? "Scrollwise, on, nothing to reverse" : "Scrollwise, not reversing"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A version number is not sensitive, and os_log redacts interpolations by
        // default — without this the launch line reads "Scrollwise <private>
        // starting", which is useless for telling which build is running.
        Log.lifecycle.info("Scrollwise \(AppInfo.version, privacy: .public) (build \(AppInfo.build, privacy: .public)) starting")

        // Before anything installs a tap: a second copy would flip every event
        // back again. See `SingleInstanceLock`.
        switch SingleInstanceLock.acquire() {
        case .acquired:
            break
        case .heldElsewhere:
            Log.lifecycle.notice("Scrollwise is already running; this copy is exiting so only one event tap exists")
            NSApp.terminate(nil)
            return
        case .unavailable(let reason):
            Log.lifecycle.error("Single-instance lock unavailable (\(reason, privacy: .public)); continuing without it")
        }

        state.start()
        SettingsWindowPresenter.shared.configure(state: state)

        Log.login.info("Login item status: \(LaunchAtLoginService.statusDescription, privacy: .public)")

        // First run with no permission: show the window so the request is
        // explained, rather than firing a bare system prompt out of nowhere.
        if !state.accessibility.allowsEngine {
            SettingsWindowPresenter.shared.show(pane: .scrolling)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutDown()
    }

    /// No Dock icon, so there is no reopen to handle — but if the app is
    /// launched a second time, surface the window instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowPresenter.shared.show()
        return true
    }
}
