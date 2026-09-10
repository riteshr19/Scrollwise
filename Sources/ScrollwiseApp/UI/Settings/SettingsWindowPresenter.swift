import AppKit
import SwiftUI
import ScrollwiseCore

/// Owns the single settings window.
///
/// An `NSWindowController` rather than SwiftUI's `Window` scene because this is
/// an `LSUIElement` app: it has no Dock icon and no menu bar of its own, so it
/// must both create the window on demand and explicitly activate itself when the
/// user picks "Settings…" from a popover that is about to close.
@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var state: AppState?

    func configure(state: AppState) {
        self.state = state
    }

    func show(pane: SettingsPane = .scrolling) {
        guard let state else {
            Log.lifecycle.error("Settings window requested before state was configured")
            return
        }

        if let window {
            // Reopening while already open should reveal it, not rebuild it.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsWindowView(initialPane: pane)
            .environment(state)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Scrollwise"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window closing must never stop the engine — the whole point of a
    /// menu-bar utility is that it keeps working with nothing on screen.
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
