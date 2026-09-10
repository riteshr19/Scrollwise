# Architecture

## Why native, not WKWebView

Three reasons, in order of weight:

1. **Liquid Glass cannot be done in a web view.** `backdrop-filter` blurs page
   content; macOS materials sample the desktop behind the window. See
   [FRONTEND-AUDIT.md](FRONTEND-AUDIT.md) §3.
2. **The bridge is pure attack surface.** §§36–37 of the brief describe a typed
   JS↔native command protocol with validation on every message. That work exists
   only to serve the web view; deleting the web view deletes the threat model.
3. **Latency.** The event tap must never contend with a web renderer.

## Targets

| Target | Kind | Imports | Holds |
|---|---|---|---|
| `ScrollwiseCore` | library | Foundation, OSLog | every decision: transformer, classifiers, latch, raw-field meaning, permission and login-item state, instance policy, settings and persistence |
| `ScrollwiseEngine` | library | Core, CoreGraphics, AppKit | `EventTapController`, `ScrollEngine`, `SnapshotBox`, `CGEventScrollAccess` |
| `ScrollwiseApp` | executable | Core, Engine, SwiftUI, IOKit, Carbon, ServiceManagement | `AppState`, services, UI |
| `ScrollwiseVerify` | executable | Core | framework-free checks of Core |
| `ScrollwiseTapCheck` | executable | Core, Engine | live checks against the real tap; needs Accessibility |
| `ScrollwiseCoreTests` | swift-testing | Core | the same checks as Verify, for machines with Xcode |

The engine is a library so `ScrollwiseTapCheck` can drive the exact code the
app ships. It is never part of the app bundle.

## Layers

```
        MenuBarView (1d)          SettingsWindowView (1b)
                    \                /
                     \              /
                      AppState  (@Observable, @MainActor)
                          |
        ┌─────────────────┼──────────────────┐
   SettingsStore      ScrollEngine      Services
   (UserDefaults)          |         (Accessibility, LoginItem,
                           |          FrontmostApp, HID, Shortcut)
                      SnapshotBox   ← the thread boundary
                           |
                   EventTapController   (dedicated thread + run loop + watchdog)
                           |
                   CGEventScrollAccess  (reads/writes integers only)
                           |
                    ScrollwiseCore   ← pure, testable, no CoreGraphics
     (RawScrollFields, DeviceClassifier, ScrollTransformer, GestureLatch)
```

## Event pipeline

```
physical scroll
  → macOS HID / window server
  → CGEventTap  (.cgSessionEventTap, .headInsertEventTap, .defaultTap,
                 mask = scrollWheel ONLY)
  → SnapshotBox.read()                      one uncontended lock
  → CGEventScrollAccess.rawFields(of:)      read 4 integers
  → DeviceClassifier.classify(fields.traits)  trackpad | mouse | tablet
  → ScrollTransformer.flip(...)             master switch → app rule → device rule
  → GestureLatch.resolve(fields, proposed:) hold the decision for this gesture
  → CGEventScrollAccess.apply(_:to:)        read 6 fields, then write 6 negated
  → return the same event
```

### What the callback is forbidden to do

No allocation, no logging, no `NSWorkspace`, no `UserDefaults`, no SwiftUI, no
Objective-C messaging into AppKit, no disk, no `await`. Everything it needs was
pre-computed by the main thread and pushed into `SnapshotBox`.

Measured with the instrumentation build (`-Xswiftc -DSCROLLWISE_INSTRUMENT`,
5,000 callbacks on the live tap): min 0.17 µs · median 0.29 µs · p95 0.96 µs ·
p99 1.62 µs · max 9.12 µs. macOS disables a tap after roughly a second.

### Why a dedicated thread

On the main run loop, any slow UI work sits directly in the path of every scroll
event, and macOS disables a tap it believes has stalled. The tap gets its own
`Thread` (`qualityOfService = .userInteractive`) and its own `CFRunLoop`, so the
two cannot interfere.

### Why all three delta representations are flipped — and in what order

macOS stores one gesture three ways per axis — line (`DeltaAxis`), pixel
(`PointDeltaAxis`), fixed-point (`FixedPtDeltaAxis`). `NSEvent.deltaY` reads the
first; `scrollingDeltaY` reads the others. Flipping one and not the others makes
an app disagree with itself.

**All three are read before any is written.** Writing the line field makes
CoreGraphics recompute the pixel and fixed-point fields from it. The first
version read each field just before negating it, so it negated the recomputed
values back to positive: measured on the live tap, `line 3 · point 30 · fixed
3.0` arrived as `line −3 · point +24 · fixed +3.0`. Every app reading precise
deltas saw the original direction. The negation is `AxisDelta.negated` from Core,
which also cannot trap on `Int64.min`.

Axis 3 and the accelerated-delta fields are deliberately untouched: no shipping
pointing device drives axis 3, and no evidence has shown the accelerated fields
to matter. That is a decision to revisit only with a device that proves otherwise.

### Why the gesture latch exists

Momentum events arrive *after* the fingers lift. If a setting changes mid-flick,
an unlatched implementation reverses the inertia but not the gesture that
launched it, and content visibly snaps direction while decelerating. The latch
holds one decision from `.began` through the final momentum event.

- Released only by `RawScrollFields.endsGesture`: momentum-phase *end*, or a
  cancelled gesture. **Scroll-phase ended does not release it** — the first
  version released there, just before the momentum it exists to protect.
- Discrete wheel clicks take the live decision and leave the latch alone, so a
  wheel tick during trackpad inertia cannot hand that inertia a new decision.
- The master switch is a setting like any other: switching it off mid-flick lets
  the gesture in flight finish as it began. Wheel clicks and the next gesture see
  it at once.

## Device classification

No public API attaches a device identifier to a `CGEvent` scroll event, so
classification is derived from the event's own traits:

| mouse subtype | `isContinuous` | phase | momentum | → |
|---|---|---|---|---|
| tablet point / proximity | *any* | *any* | *any* | tablet |
| – | *any* | ✓ | – | trackpad |
| – | *any* | – | ✓ | trackpad (inertia) |
| – | ✓ | – | – | mouse (high-resolution wheel) |
| – | – | – | – | mouse (conventional wheel) |

- **Magic Mouse follows the Trackpad rule.** Its touch surface produces phased,
  momentum-bearing events indistinguishable from a trackpad's. The Devices pane
  lists it under Trackpad and says so.
- **The tablet path is unverified on hardware.** A synthetic scroll event's
  tablet subtype arrives at the tap as `0`, so no automated test can reach it;
  whether a given tablet driver marks its scroll events is a manual check.
- `unknown` resolves to the mouse rule.

`HIDDeviceInventory` enumerates real hardware names via IOKit **for display
only**. It never opens the HID devices, so it needs no Input Monitoring
permission.

## Settings

One `Codable` struct, persisted as a single JSON blob under `settings.v1`, so a
save is atomic and the engine can never observe half a change.

Settings are external data, so reading them is defensive:

- **Lenient decoding.** Each field falls back to its own default when missing or
  malformed; array elements that do not decode are dropped individually. The
  synthesized decoder threw on any missing key, which would have reset every user
  to defaults the first time a field was added.
- **Normalization.** At least one profile, an active profile that exists, unique
  app-rule and profile identities. `activeProfile` cannot trap even on a
  hand-built value with no profiles — the tap reads it per event.
- **Unreadable data is kept** under `settings.v1.unreadable` rather than being
  overwritten by the next save.
- `schemaVersion` marks where the first non-additive change will migrate.

Mutation is immutable throughout; `AppState.commit` is the single write path
(persist, then push the complete value into the snapshot in one swap).

## Permission lifecycle

```
launch → AXIsProcessTrusted()
   ├── true  → engine.start() → .starting → tap attaches → .running
   └── false → engine stays stopped
               settings window opens explaining why
               1 Hz poll notices the grant (macOS posts no notification)
               engine.reconcile(.granted) → start()
```

`AccessibilityStatus` (Core) decides every transition:

- **Tap failure is sticky while trust holds.** If the API reports trust but the
  tap will not attach, the state becomes `.grantedButTapFailed`. The poll used to
  turn it straight back into `.granted`, restarting the tap every second and
  briefly claiming it ran. Now only losing trust (removing and re-adding the app)
  or a tap that attaches clears it.
- The engine retries a failed tap every 30 s and on wake, so a transient refusal
  recovers without the user.

## Engine states

`ScrollEngine.State` is what the engine is doing, reported only from what the tap
thread observed: `.stopped`, `.starting`, `.running`, `.failed`. It never reads
`.running` because a start was requested — only once the tap says it is installed.

## Recovery

| Event | Handling |
|---|---|
| macOS disables the tap | Watchdog on the tap thread (1 s, 0.5 s tolerance) re-enables it and resets the latch. `tapDisabledByTimeout` in the callback does the same when it arrives — measured on macOS 26.5, after a stall it **did not arrive at all**, so the watchdog is what actually recovers |
| Wake from sleep | `NSWorkspace.didWakeNotification` → re-arm, or retry a failed tap |
| Tap creation fails while trusted | `.failed`; retried every 30 s and on wake |
| Permission revoked | 1 Hz poll → `engine.stop()` |
| Permission granted | 1 Hz poll → `engine.start()` |
| A second copy launched | `SingleInstanceLock`: an exclusive `flock` taken before any tap; the loser exits. Atomic, so two copies launched in the same instant cannot both stay (a `NSRunningApplication` snapshot could) |
| Settings changed | New snapshot pushed; no restart |
| Quit | `stop()` waits for the tap thread to remove the tap and exit |

## Threading

| Thread | Work |
|---|---|
| Main | All UI, `AppState`, services, settings writes, `ScrollEngine` |
| `engineer.riteshrana.scrollwise.eventtap` | Tap callback, watchdog, re-enable |

Shared between them, and nothing else:

- `SnapshotBox` (`OSAllocatedUnfairLock`): the settings and frontmost app.
- `EventTapController`'s lifecycle fields (`hasStarted`, `isCancelled`,
  `runLoop`) under an `NSLock`. `tap` and the latch are touched only on the tap
  thread; `reenableIfNeeded()` hops there with `CFRunLoopPerformBlock`.
- Reports from the tap thread reach the main actor as a `Task`, carrying the
  reporting controller's identity so a stopped controller's late report is ignored.

## Lifecycle guarantees

- A controller starts once and cannot restart; `ScrollEngine` makes a new one.
- `stop()` works at any moment, including before the thread has created the tap,
  and returns only once the tap is gone and the thread has exited. The first
  version returned without effect when called before the thread published its run
  loop — that thread then installed a tap nothing could remove, and the next start
  added a second, which flips every event back.
- Measured with `ScrollwiseTapCheck`: 200 stops racing their starts leave 0 taps;
  100 engine stop/start cycles leave 0; never more than one at a time.

## Entitlements

App Sandbox is **not** requested: a sandboxed process cannot hold the
Accessibility right an event tap requires. The only entitlement in the signed
bundle is `com.apple.security.automation.apple-events = false`. No network, no
camera, no microphone, no Input Monitoring.

No private API is used anywhere.
