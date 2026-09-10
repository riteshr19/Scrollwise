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
public struct EngineSnapshot: Sendable {
    public var settings: ScrollSettings
    public var frontmostBundleID: String?

    public init(settings: ScrollSettings = SettingsDefaults.settings, frontmostBundleID: String? = nil) {
        self.settings = settings
        self.frontmostBundleID = frontmostBundleID
    }
}

/// Lock-protected snapshot shared between the main thread (writer) and the event
/// tap thread (reader). `OSAllocatedUnfairLock` is used rather than a queue
/// because the read must complete in nanoseconds and must never hop threads.
///
/// Each update replaces one whole field under the lock, and each read copies the
/// whole value under the lock, so a reader sees either all of a settings change
/// or none of it — never one device's rule from before and another's from after.
public final class SnapshotBox: Sendable {
    private let storage: OSAllocatedUnfairLock<EngineSnapshot>

    public init(_ initial: EngineSnapshot = EngineSnapshot()) {
        storage = OSAllocatedUnfairLock(initialState: initial)
    }

    /// Called from the event tap thread, once per scroll event.
    public func read() -> EngineSnapshot {
        storage.withLock { $0 }
    }

    /// Called from the main thread when settings or the frontmost app change.
    public func updateSettings(_ settings: ScrollSettings) {
        storage.withLock { $0.settings = settings }
    }

    public func updateFrontmostBundleID(_ bundleID: String?) {
        storage.withLock { $0.frontmostBundleID = bundleID }
    }
}
