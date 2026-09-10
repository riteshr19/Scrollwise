import CoreGraphics
import Foundation
import ScrollwiseCore
import ScrollwiseEngine

enum Harness {
    /// Stamped into `eventSourceUserData` on every event this tool posts, so the
    /// observer handles only its own events and leaves real input alone.
    static let marker: Int64 = 0x5343_524C  // "SCRL"
    static let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
}

/// A tap at the *tail* of the session chain. It sees each posted event after the
/// engine's head-inserted tap has modified it — what an app would receive — and
/// then consumes it, so nothing on screen actually scrolls.
final class Observer: @unchecked Sendable {
    /// One event as an app would have received it.
    struct Seen {
        let delta: ScrollDelta
        let mouseSubtype: Int64
    }

    private let lock = NSLock()
    private var seen: [Seen] = []
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)

    func start() -> Bool {
        Thread { self.run() }.start()
        ready.wait()
        return lock.withLock { tap != nil }
    }

    func stop() {
        guard let loop = lock.withLock({ loop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
        exited.wait()
    }

    var count: Int { lock.withLock { seen.count } }

    func take() -> [Seen] {
        lock.withLock {
            defer { seen = [] }
            return seen
        }
    }

    private func run() {
        defer { exited.signal() }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: Harness.scrollMask,
            callback: observerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            ready.signal()
            return
        }
        let current: CFRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        lock.withLock {
            tap = port
            loop = current
        }
        ready.signal()
        CFRunLoopRun()
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(current, source, .commonModes)
        CFMachPortInvalidate(port)
        lock.withLock {
            tap = nil
            loop = nil
        }
    }

    fileprivate func observe(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) == Harness.marker else {
            return Unmanaged.passUnretained(event)
        }
        let observed = Seen(
            delta: CGEventScrollAccess.delta(of: event),
            mouseSubtype: event.getIntegerValueField(.mouseEventSubtype)
        )
        lock.withLock { seen.append(observed) }
        return nil
    }
}

private let observerCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<Observer>.fromOpaque(userInfo).takeUnretainedValue().observe(type, event)
}

/// Thread-safe record of what a controller reported.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [EventTapController.Event] = []

    func append(_ event: EventTapController.Event) {
        lock.withLock { events.append(event) }
    }

    func count(of event: EventTapController.Event) -> Int {
        lock.withLock { events.filter { $0 == event }.count }
    }
}

/// One synthetic scroll event, built the way hardware of each class sends it.
struct ScrollPost {
    var vertical: Int32 = 3
    var horizontal: Int32 = 0
    var isContinuous = false
    var scrollPhase: Int64 = 0
    var momentumPhase: Int64 = 0
    var mouseSubtype: Int64 = 0

    /// A conventional wheel click.
    static let wheel = ScrollPost()

    /// A trackpad event at the given point of a gesture.
    static func trackpad(scroll: Int64 = 0, momentum: Int64 = 0) -> ScrollPost {
        ScrollPost(isContinuous: true, scrollPhase: scroll, momentumPhase: momentum)
    }

    /// Posts the event and returns its deltas as created, to compare with what arrives.
    func send() -> ScrollDelta? {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .line,
            wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0
        ) else { return nil }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: isContinuous ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setIntegerValueField(.mouseEventSubtype, value: mouseSubtype)
        event.setIntegerValueField(.eventSourceUserData, value: Harness.marker)
        let original = CGEventScrollAccess.delta(of: event)
        event.post(tap: .cghidEventTap)
        return original
    }
}

/// Every tap in the session, or those owned by one process.
func eventTaps(ofPID pid: pid_t? = nil) -> [CGEventTapInformation] {
    var count: UInt32 = 0
    guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    guard CGGetEventTapList(count, &list, &count) == .success else { return [] }
    let all = Array(list.prefix(Int(count)))
    guard let pid else { return all }
    return all.filter { $0.tappingProcess == pid }
}

func percentile(_ sorted: [UInt64], _ p: Double) -> UInt64 {
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
    return sorted[index]
}
