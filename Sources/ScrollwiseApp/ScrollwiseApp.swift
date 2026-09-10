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
                .accessibilityLabel(delegate.state.isActive
                                    ? "Scrollwise, reversing"
                                    : "Scrollwise, not reversing")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()
    private let shortcuts = GlobalShortcutService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A version number is not sensitive, and os_log redacts interpolations by
        // default — without this the launch line reads "Scrollwise <private>
        // starting", which is useless for telling which build is running.
        Log.lifecycle.info("Scrollwise \(AppInfo.version, privacy: .public) (build \(AppInfo.build, privacy: .public)) starting")

        state.start()
        SettingsWindowPresenter.shared.configure(state: state)

        Log.login.info("Login item status: \(LaunchAtLoginService.statusDescription, privacy: .public)")

        shortcuts.register { [weak state] in
            state?.toggleEnabled()
        }

        // First run with no permission: show the window so the request is
        // explained, rather than firing a bare system prompt out of nowhere.
        if !state.accessibility.allowsEngine {
            SettingsWindowPresenter.shared.show(pane: .scrolling)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.unregister()
        state.shutDown()
    }

    /// No Dock icon, so there is no reopen to handle — but if the app is
    /// launched a second time, surface the window instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowPresenter.shared.show()
        return true
    }
}
