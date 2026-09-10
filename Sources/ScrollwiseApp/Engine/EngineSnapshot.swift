import Foundation
import os
import ScrollwiseCore

/// Everything the event callback needs, pre-computed, so the hot path never has
/// to ask anyone a question.
///
/// The callback must not touch `NSWorkspace`, `UserDefaults`, SwiftUI state, or
/// anything main-thread-bound: any of those can block long enough for macOS to
/// decide the tap is unresponsive and switch it off. Instead the main thread
/// pushes a fresh snapshot in whenever something changes, and the callback takes
/// an uncontended lock to copy it out.
struct EngineSnapshot: Sendable {
    var settings: ScrollSettings
    var frontmostBundleID: String?

    init(settings: ScrollSettings = SettingsDefaults.settings, frontmostBundleID: String? = nil) {
        self.settings = settings
        self.frontmostBundleID = frontmostBundleID
    }
}

/// Lock-protected snapshot shared between the main thread (writer) and the event
/// tap thread (reader). `OSAllocatedUnfairLock` is used rather than a queue
/// because the read must complete in nanoseconds and must never hop threads.
final class SnapshotBox: Sendable {
    private let storage: OSAllocatedUnfairLock<EngineSnapshot>

    init(_ initial: EngineSnapshot = EngineSnapshot()) {
        storage = OSAllocatedUnfairLock(initialState: initial)
    }

    /// Called from the event tap thread, once per scroll event.
    func read() -> EngineSnapshot {
        storage.withLock { $0 }
    }

    /// Called from the main thread when settings or the frontmost app change.
    func updateSettings(_ settings: ScrollSettings) {
        storage.withLock { $0.settings = settings }
    }

    func updateFrontmostBundleID(_ bundleID: String?) {
        storage.withLock { $0.frontmostBundleID = bundleID }
    }
}
