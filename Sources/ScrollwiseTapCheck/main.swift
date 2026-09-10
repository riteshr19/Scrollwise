import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScrollwiseCore
import ScrollwiseEngine

// Live checks against the real event tap.
//
// ScrollwiseVerify proves the decisions; this proves the machinery that carries
// them out: that a tap is attached exactly once, that what an app receives is
// really reversed, that momentum keeps its gesture's decision on the live path,
// and that the tap recovers when macOS switches it off. It needs Accessibility —
// it creates taps and posts events — so it runs by hand, not in CI.
//
//   swift run ScrollwiseTapCheck
//   swift run -Xswiftc -DSCROLLWISE_INSTRUMENT ScrollwiseTapCheck   # + recovery, callback timing
//
// Every event it posts is stamped and consumed by `Observer` at the tail of the
// session, so no app scrolls while it runs.

var failures: [String] = []
var checks = 0
var notRun: [String] = []
let me = getpid()

@MainActor
func expect(_ condition: Bool, _ label: String) {
    checks += 1
    print(condition ? "  ✓ \(label)" : "  ✗ \(label)")
    if !condition { failures.append(label) }
}

@MainActor
func section(_ title: String) {
    print("\n\(title)")
}

/// Runs the main run loop until `condition` holds or `timeout` passes, so
/// main-actor work the engine schedules gets to run meanwhile.
@MainActor
@discardableResult
func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    return true
}

@MainActor
func pause(_ seconds: TimeInterval) {
    waitUntil(seconds) { false }
}

func settings(
    trackpad: Bool = false,
    mouse: Bool = true,
    tablet: Bool = false,
    horizontal: Bool = false,
    enabled: Bool = true,
    appRules: [AppRule] = []
) -> ScrollSettings {
    let id = SettingsDefaults.defaultProfileID
    return ScrollSettings(
        isEnabled: enabled,
        profiles: [Profile(id: id, name: "Check", deviceRules: [
            DeviceRule(device: .trackpad, reverseVertical: trackpad),
            DeviceRule(device: .mouse, reverseVertical: mouse, reverseHorizontal: horizontal),
            DeviceRule(device: .tablet, reverseVertical: tablet),
        ])],
        activeProfileID: id,
        appRules: appRules,
        launchAtLogin: false,
        defaultForNewDevices: DeviceRule(device: .mouse, reverseVertical: true)
    )
}

let vertical = AxisFlip(vertical: true, horizontal: false)
let bothAxes = AxisFlip(vertical: true, horizontal: true)
typealias Phase = RawScrollFields.ScrollPhase
typealias Momentum = RawScrollFields.MomentumPhase

// MARK: - Preconditions

@MainActor
func checkPreconditions() {
    print("ScrollwiseTapCheck — live checks against the real event tap")
    guard AXIsProcessTrusted() else {
        print("BLOCKED — this process is not trusted for Accessibility, so it cannot create a tap.")
        print("Run it from a terminal allowed in System Settings › Privacy & Security › Accessibility.")
        exit(2)
    }
    let rivals = eventTaps().filter { tap in
        tap.tappingProcess != me && tap.enabled && tap.options == .defaultTap
            && (tap.eventsOfInterest & Harness.scrollMask) != 0
    }
    for tap in rivals {
        let app = NSRunningApplication(processIdentifier: tap.tappingProcess)
        if app?.bundleIdentifier == "engineer.riteshrana.scrollwise" {
            print("BLOCKED — Scrollwise is running as pid \(tap.tappingProcess) and would flip these events too.")
            print("Quit it and run again.")
            exit(2)
        }
        print("  note: pid \(tap.tappingProcess) (\(app?.localizedName ?? "unknown")) also has an active scroll tap")
    }
}

// MARK: - 1. Controller

@MainActor
func checkControllerLifecycle() {
    section("1. One controller, one tap")

    let log = EventLog()
    let controller = EventTapController(snapshot: SnapshotBox()) { _, event in log.append(event) }
    controller.start()
    expect(waitUntil(2) { log.count(of: .installed) == 1 }, "a started tap reports that it is installed")
    let running = eventTaps(ofPID: me)
    expect(running.count == 1, "exactly one tap exists while it runs (found \(running.count))")
    expect(running.first?.eventsOfInterest == Harness.scrollMask,
           "its mask is scroll wheel only — no keys, clicks, movement or gestures")
    expect(running.first?.options == .defaultTap, "it is an active tap, able to modify events")
    controller.start()
    expect(eventTaps(ofPID: me).count == 1, "starting it again adds no second tap")
    controller.stop()
    expect(eventTaps(ofPID: me).isEmpty, "stop() returns only once the tap is gone")
    controller.stop()
    controller.start()
    pause(0.2)
    expect(eventTaps(ofPID: me).isEmpty && !controller.isRunning, "a stopped controller cannot be started again")

    // The race that used to leak: stop() arriving before the thread had
    // published its run loop returned without effect, and the thread then
    // installed a tap nothing could remove.
    var leaked = 0
    var peak = 0
    for _ in 0..<200 {
        let racer = EventTapController(snapshot: SnapshotBox()) { _, _ in }
        racer.start()
        peak = max(peak, eventTaps(ofPID: me).count)
        racer.stop()
        if !eventTaps(ofPID: me).isEmpty { leaked += 1 }
    }
    expect(leaked == 0, "200 stops racing their starts leave no tap behind (\(leaked) leaked)")
    expect(peak <= 1, "never more than one tap at a time (peak \(peak))")
}

// MARK: - 2. Engine

@MainActor
func checkEngineLifecycle() {
    section("2. Engine lifecycle")

    let engine = ScrollEngine(snapshot: SnapshotBox(), isTrusted: { true })
    var states: [ScrollEngine.State] = []
    engine.onStateChange = { states.append($0) }

    engine.start()
    engine.start()
    expect(engine.state == .starting, "a requested tap is 'starting', never 'running' on request alone")
    expect(waitUntil(2) { engine.state == .running }, "the engine reports running once the tap attaches")
    expect(eventTaps(ofPID: me).count == 1, "two start() calls make one tap")
    expect(states == [.starting, .running], "states are reported in order (\(states))")

    engine.handleWake()
    pause(0.1)
    expect(engine.state == .running && eventTaps(ofPID: me).count == 1,
           "wake re-arms the existing tap without adding one")

    engine.stop()
    expect(engine.state == .stopped && eventTaps(ofPID: me).isEmpty, "stop removes the tap before returning")

    engine.start()
    waitUntil(2) { engine.state == .running }
    expect(eventTaps(ofPID: me).count == 1, "stop then start leaves exactly one working tap")

    for _ in 0..<100 {
        engine.stop()
        engine.start()
    }
    engine.stop()
    pause(0.3)  // let every late report from a replaced tap arrive
    expect(engine.state == .stopped, "late reports from replaced taps are ignored (state \(engine.state))")
    expect(eventTaps(ofPID: me).isEmpty, "100 rapid stop/start cycles leave no tap")

    engine.reconcile(with: .granted)
    waitUntil(2) { engine.state == .running }
    engine.reconcile(with: .grantedButTapFailed)
    expect(engine.state == .running && eventTaps(ofPID: me).count == 1,
           "a tap-failure status does not tear down a tap that works")
    engine.reconcile(with: .denied)
    expect(engine.state == .stopped && eventTaps(ofPID: me).isEmpty,
           "losing permission stops the engine and removes the tap")

    let untrusted = ScrollEngine(snapshot: SnapshotBox(), isTrusted: { false })
    untrusted.start()
    expect(untrusted.state == .stopped && eventTaps(ofPID: me).isEmpty,
           "without trust the engine does not even try")
}

// MARK: - Delivery

/// Posts one event; returns it as created and as an app would have received it.
@MainActor
func deliverThrough(_ observer: Observer, _ post: ScrollPost) -> (sent: ScrollDelta, seen: ScrollDelta, subtype: Int64)? {
    _ = observer.take()
    guard let sent = post.send(), waitUntil(2, { observer.count >= 1 }),
          let seen = observer.take().first else { return nil }
    return (sent, seen.delta, seen.mouseSubtype)
}

@MainActor
func checkDelivery(through observer: Observer, _ post: ScrollPost, _ flip: AxisFlip, _ label: String) {
    guard let result = deliverThrough(observer, post) else {
        expect(false, "\(label) — the event never arrived")
        return
    }
    let expected = result.sent.applying(flip)
    let matched = result.seen == expected
    expect(matched, matched ? label : "\(label) — sent \(result.sent), expected \(expected), got \(result.seen)")
}

// MARK: - The installed app

/// `--running-app`: the same end-to-end check against a real, running
/// Scrollwise bundle rather than an engine this tool created. Proves the
/// shipped app — its signature, its TCC grant, its stored settings — actually
/// reverses what an app receives.
@MainActor
func checkRunningApp() {
    print("ScrollwiseTapCheck --running-app — end to end against the running Scrollwise bundle")
    guard AXIsProcessTrusted() else {
        print("BLOCKED — this process is not trusted for Accessibility, so it cannot post or observe events.")
        exit(2)
    }
    let bundleID = "engineer.riteshrana.scrollwise"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    section("Process")
    expect(running.count == 1, "exactly one Scrollwise process is running (found \(running.count))")
    guard let app = running.first else { return }
    print("  pid \(app.processIdentifier) · \(app.bundleURL?.path ?? "unknown path")")
    let taps = eventTaps(ofPID: app.processIdentifier)
    expect(taps.count == 1, "it holds exactly one event tap (found \(taps.count))")
    expect(taps.first?.eventsOfInterest == Harness.scrollMask, "the tap's mask is scroll wheel only")
    expect(taps.first?.options == .defaultTap && taps.first?.enabled == true, "the tap is active and enabled")

    guard let domain = UserDefaults(suiteName: bundleID) else {
        expect(false, "the app's settings can be read")
        return
    }
    let stored = SettingsStore(defaults: domain).load()
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    let wheel = ScrollTransformer.flip(device: .mouse, frontmostBundleID: frontmost, settings: stored)
    let trackpad = ScrollTransformer.flip(device: .trackpad, frontmostBundleID: frontmost, settings: stored)

    let observer = Observer()
    guard observer.start() else {
        print("BLOCKED — could not attach the observer")
        exit(2)
    }
    section("What an app receives (frontmost: \(frontmost ?? "none"))")
    checkDelivery(through: observer, .wheel, wheel,
                  "a wheel click arrives \(wheel.isIdentity ? "natural" : "reversed"), as the stored settings say")
    checkDelivery(through: observer, .trackpad(scroll: Phase.began), trackpad,
                  "a trackpad gesture arrives \(trackpad.isIdentity ? "natural" : "reversed"), as the stored settings say")
    _ = deliverThrough(observer, .trackpad(scroll: Phase.cancelled))
    observer.stop()
}

@MainActor
func report() -> Never {
    print("")
    if failures.isEmpty {
        let suffix = notRun.isEmpty ? "" : " (\(notRun.count) not run: \(notRun.joined(separator: "; ")))"
        print("PASS — \(checks) live checks\(suffix)")
        exit(0)
    }
    print("FAIL — \(failures.count) of \(checks) live checks failed:")
    failures.forEach { print("  ✗ \($0)") }
    exit(1)
}

// MARK: - 3–7. The live path

/// A running controller plus the observer that reads what it delivered.
@MainActor
final class LivePath {
    let observer: Observer
    let observerTapID: UInt32?
    let box = SnapshotBox(EngineSnapshot(settings: settings()))
    let log = EventLog()
    private(set) var controller: EventTapController

    init?() {
        observer = Observer()
        guard observer.start() else { return nil }
        observerTapID = eventTaps(ofPID: me).first?.eventTapID
        let log = self.log
        controller = EventTapController(snapshot: box) { _, event in log.append(event) }
        controller.start()
        guard waitUntil(2, { log.count(of: .installed) == 1 }) else { return nil }
    }

    /// The engine's tap, as the window server sees it.
    var engineTap: CGEventTapInformation? {
        eventTaps(ofPID: me).first { $0.eventTapID != observerTapID }
    }

    /// Replaces the controller with a fresh one, for statistics that start clean.
    func restart() {
        controller.stop()
        let log = self.log
        controller = EventTapController(snapshot: box) { _, event in log.append(event) }
        controller.start()
        waitUntil(2) { self.controller.isRunning }
    }

    func deliver(_ post: ScrollPost) -> (sent: ScrollDelta, seen: ScrollDelta, subtype: Int64)? {
        deliverThrough(observer, post)
    }

    func check(_ post: ScrollPost, _ flip: AxisFlip, _ label: String) {
        checkDelivery(through: observer, post, flip, label)
    }

    func finish() {
        controller.stop()
        observer.stop()
    }
}

@MainActor
func checkDirection(_ live: LivePath) {
    section("3. End-to-end direction")

    live.box.updateSettings(settings(mouse: true))
    live.check(.wheel, vertical, "a wheel click is reversed — line, pixel and fixed-point together")
    live.check(.trackpad(scroll: Phase.began), .none, "a trackpad gesture is left natural under the default rules")
    _ = live.deliver(.trackpad(scroll: Phase.cancelled))

    live.box.updateSettings(settings(mouse: true, horizontal: true))
    live.check(ScrollPost(vertical: 3, horizontal: -2), bothAxes, "horizontal is reversed when opted in")
    live.box.updateSettings(settings(mouse: true, horizontal: false))
    live.check(ScrollPost(vertical: 3, horizontal: -2), vertical, "and left exactly as it was otherwise")

    live.box.updateSettings(settings(enabled: false))
    live.check(.wheel, .none, "the master switch off passes a wheel click through untouched")

    live.box.updateSettings(settings(appRules: [
        AppRule(bundleIdentifier: "com.example.skip", displayName: "Skip", action: .passthrough),
    ]))
    live.box.updateFrontmostBundleID("com.example.skip")
    live.check(.wheel, .none, "a passthrough app rule beats the mouse rule while its app is frontmost")
    live.box.updateFrontmostBundleID("com.example.other")
    live.check(.wheel, vertical, "and applies to no other app")
    live.box.updateFrontmostBundleID(nil)

    // Tablet classification rests on the event's mouse subtype. Whether a
    // posted scroll event can carry one is itself the first question: if the
    // window server clears it, no synthetic test can reach the Tablet rule and
    // that path needs a real tablet.
    live.box.updateSettings(settings(enabled: false))
    let tabletPost = ScrollPost(mouseSubtype: RawScrollFields.MouseSubtype.tabletPoint)
    let arrivedSubtype = live.deliver(tabletPost)?.subtype
    if arrivedSubtype == RawScrollFields.MouseSubtype.tabletPoint {
        live.box.updateSettings(settings(mouse: true, tablet: false))
        live.check(tabletPost, .none, "an event marked as a tablet pointer follows the Tablet rule, not the Mouse rule")
        live.box.updateSettings(settings(mouse: false, tablet: true))
        live.check(tabletPost, vertical, "and the Tablet rule reverses it when set")
    } else {
        notRun.append("Tablet rule on the live path — a posted scroll event's subtype arrives as \(arrivedSubtype.map(String.init) ?? "nothing"), so only a real tablet can exercise it")
        print("  – not run: a posted scroll event's tablet subtype arrives as \(arrivedSubtype.map(String.init) ?? "nothing"); needs a real tablet")
    }
}

@MainActor
func checkLatch(_ live: LivePath) {
    section("4. Gesture latch on the live tap")

    live.box.updateSettings(settings(trackpad: true))
    live.check(.trackpad(scroll: Phase.began), vertical, "a reversed trackpad gesture begins reversed")
    live.check(.trackpad(scroll: Phase.changed), vertical, "and continues reversed")
    live.box.updateSettings(settings(trackpad: false))  // the setting changes mid-flick
    live.check(.trackpad(scroll: Phase.changed), vertical, "a mid-gesture setting change leaves the moving fingers alone")
    live.check(.trackpad(scroll: Phase.ended), vertical, "the lift keeps the gesture's decision")
    live.check(.trackpad(momentum: Momentum.begin), vertical,
               "momentum after the lift keeps it too — where the old latch release reversed the inertia")
    live.check(.wheel, vertical, "a wheel click during that inertia follows its own live rule")
    live.check(.trackpad(momentum: Momentum.continuing), vertical, "and does not disturb the trackpad's latch")
    live.check(.trackpad(momentum: Momentum.end), vertical, "the last momentum event still matches")
    live.check(.trackpad(scroll: Phase.began), .none, "the next gesture picks up the new setting")
    _ = live.deliver(.trackpad(scroll: Phase.cancelled))

    live.box.updateSettings(settings(trackpad: true))
    live.check(.trackpad(scroll: Phase.began), vertical, "a reversed gesture begins")
    live.box.updateSettings(settings(trackpad: true, enabled: false))
    live.check(.trackpad(scroll: Phase.ended), vertical,
               "switching the master switch off mid-flick lets the gesture in flight finish as it began")
    live.check(.trackpad(momentum: Momentum.end), vertical, "through its last momentum event")
    live.check(.wheel, .none, "a wheel click sees the switch at once")
    live.check(.trackpad(scroll: Phase.began), .none, "and so does the next gesture")
    _ = live.deliver(.trackpad(scroll: Phase.cancelled))
}

@MainActor
func checkRecovery(_ live: LivePath) {
    section("5. Recovery when macOS disables the tap")
    #if SCROLLWISE_INSTRUMENT
    live.box.updateSettings(settings(mouse: true))
    let log = live.log
    for cycle in 1...3 {
        let notifiedBefore = log.count(of: .disabledByTimeout) + log.count(of: .disabledByUserInput)
        let watchdogBefore = log.count(of: .reenabled)
        let stalledAt = Date()
        live.controller.instrument.stallNextCallback(nanoseconds: 2_500_000_000)
        _ = ScrollPost.wheel.send()
        let noticed = waitUntil(10) {
            log.count(of: .disabledByTimeout) + log.count(of: .disabledByUserInput) > notifiedBefore
                || log.count(of: .reenabled) > watchdogBefore
        }
        let elapsed = Date().timeIntervalSince(stalledAt)
        expect(noticed, "cycle \(cycle): the disabled tap was noticed")
        pause(0.3)
        let notified = log.count(of: .disabledByTimeout) + log.count(of: .disabledByUserInput) - notifiedBefore
        let watchdog = log.count(of: .reenabled) - watchdogBefore
        print(String(format: "    noticed %.1f s after the stall began — callback notifications: %d · watchdog re-enables: %d",
                     elapsed, notified, watchdog))
        _ = live.observer.take()
        expect(live.engineTap?.enabled == true, "cycle \(cycle): the tap is enabled again")
        live.check(.wheel, vertical, "cycle \(cycle): scrolling is reversed again, with no restart")
    }
    #else
    notRun.append("recovery from tapDisabledByTimeout")
    print("  – not run: needs an instrumentation build (-Xswiftc -DSCROLLWISE_INSTRUMENT)")
    #endif
}

@MainActor
func checkLatency(_ live: LivePath) {
    section("6. Callback latency")
    live.box.updateSettings(settings(mouse: true))
    live.restart()  // fresh window-server statistics and a fresh sample buffer

    let burst = 5_000
    _ = live.observer.take()
    for index in 0..<burst {
        var post = ScrollPost.wheel
        post.vertical = index.isMultiple(of: 2) ? 1 : -1
        _ = post.send()
        if index % 250 == 249 { pause(0.005) }
    }
    let arrived = waitUntil(20) { live.observer.count >= burst }
    expect(arrived, "all \(burst) events passed through the tap (\(live.observer.count) arrived)")

    if let tap = live.engineTap {
        print(String(format: "  window server's measurement of this tap: min %.1f µs · avg %.1f µs · max %.1f µs",
                     tap.minUsecLatency, tap.avgUsecLatency, tap.maxUsecLatency))
    }

    #if SCROLLWISE_INSTRUMENT
    live.controller.stop()
    let samples = live.controller.instrument.durations().sorted()
    expect(samples.count >= burst, "every callback was timed (\(samples.count) samples)")
    let micro = { (ns: UInt64) in String(format: "%.2f µs", Double(ns) / 1_000) }
    print("  callback, \(samples.count) samples: min \(micro(samples.first ?? 0)) · median \(micro(percentile(samples, 0.5))) · p95 \(micro(percentile(samples, 0.95))) · p99 \(micro(percentile(samples, 0.99))) · max \(micro(samples.last ?? 0))")
    // macOS disables a tap after roughly a second without an answer. These
    // bounds are orders of magnitude inside that, and still catch any
    // accidental blocking work in the callback.
    expect(percentile(samples, 0.99) < 1_000_000, "p99 callback time is under 1 ms")
    expect((samples.last ?? 0) < 20_000_000, "the slowest callback is under 20 ms")
    #else
    notRun.append("in-callback timing percentiles")
    print("  – percentiles not run: needs an instrumentation build")
    #endif
}

@MainActor
func checkTeardown(_ live: LivePath) {
    section("7. Teardown")
    live.finish()
    expect(eventTaps(ofPID: me).isEmpty, "nothing is left attached")
}

// MARK: - Run

if CommandLine.arguments.contains("--running-app") {
    checkRunningApp()
    report()
}

checkPreconditions()
checkControllerLifecycle()
checkEngineLifecycle()

if let live = LivePath() {
    checkDirection(live)
    checkLatch(live)
    checkRecovery(live)
    checkLatency(live)
    checkTeardown(live)
} else {
    print("BLOCKED — could not attach the observer or the engine tap")
    exit(2)
}

report()
