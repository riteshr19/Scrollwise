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
                   EventTapController   (dedicated thread + run loop)
                           |
                   CGEventScrollAccess
                           |
                    ScrollwiseCore   ← pure, testable, no CoreGraphics
              (DeviceClassifier, ScrollTransformer, GestureLatch)
```

`ScrollwiseCore` is a separate target with no AppKit or CoreGraphics
dependency at all. That is what makes the transformation logic testable without
synthesising physical input, per §49 of the brief.

## Event pipeline

```
physical scroll
  → macOS HID / window server
  → CGEventTap  (.cgSessionEventTap, .headInsertEventTap, .defaultTap,
                 mask = scrollWheel ONLY)
  → CGEventScrollAccess.traits(of:)      read 3 integers
  → DeviceClassifier.classify(_:)        trackpad | mouse | tablet | unknown
  → SnapshotBox.read()                   one uncontended lock
  → ScrollTransformer.flip(...)          settings + app rule → AxisFlip
  → GestureLatch.resolve(...)            hold the decision for this gesture
  → CGEventScrollAccess.apply(_:to:)     negate 6 fields in place
  → return the same event
```

### What the callback is forbidden to do

No allocation, no logging, no `NSWorkspace`, no `UserDefaults`, no SwiftUI, no
Objective-C messaging into AppKit, no disk, no `await`. Everything it needs was
pre-computed by the main thread and pushed into `SnapshotBox`.

### Why a dedicated thread

On the main run loop, any slow UI work sits directly in the path of every scroll
event, and macOS disables a tap it believes has stalled. The tap gets its own
`Thread` (`qualityOfService = .userInteractive`) and its own `CFRunLoop`, so the
two cannot interfere.

### Why all three delta representations are flipped

macOS stores one gesture three ways per axis — line (`DeltaAxis`), pixel
(`PointDeltaAxis`), fixed-point (`FixedPtDeltaAxis`). `NSEvent.deltaY` reads the
first; `scrollingDeltaY` reads the third. Flipping one and not the others makes
an app disagree with itself, which is the usual cause of jitter and
half-reversed momentum. Axis 3 and the accelerated-delta fields are deliberately
untouched.

### Why the gesture latch exists

Momentum events arrive *after* the fingers lift. If a setting changes mid-flick,
an unlatched implementation reverses the inertia but not the gesture that
launched it, and content visibly snaps direction while decelerating. The latch
holds one decision from `.began` through the final momentum event. Discrete
wheel clicks are never latched.

## Device classification

No public API attaches a device identifier to a `CGEvent` scroll event, so
classification is derived from the event's own traits:

| `isContinuous` | phase | momentum | → |
|---|---|---|---|
| ✓ | ✓ | – | trackpad |
| ✓ | – | ✓ | trackpad (inertia) |
| ✓ | – | – | mouse (high-resolution wheel) |
| – | – | – | mouse (conventional wheel) |
| *any* | *any* | *any* | tablet, if the tablet subtype is set |

`unknown` resolves to the mouse rule — the safe default, since a device
reporting no phase behaves like a wheel.

`HIDDeviceInventory` enumerates real hardware names via IOKit **for display
only**. It never opens the HID devices, so it needs no Input Monitoring
permission — reading matched device properties requires none.

## Settings

One `Codable` struct, persisted as a single JSON blob under `settings.v1`. One
blob rather than scattered keys so a save is atomic and the engine can never
observe half a change. Load failures fall back to defaults rather than throwing:
a settings problem must not stop scrolling from working. `schemaVersion` carries
a migration hook.

**Defaults:** trackpad natural, mouse reversed, vertical only, enabled,
launch-at-login off. Rationale in `SettingsDefaults`.

Mutation is immutable throughout — `replacingActiveRule` and friends return
copies; `AppState.commit` is the single write path (persist, then push a
snapshot to the engine).

## Permission lifecycle

```
launch → AXIsProcessTrusted()
   ├── true  → engine.start() → tap created → running
   └── false → engine stays stopped
               settings window opens explaining why
               user opens System Settings
               1 Hz poll notices the change (macOS posts no notification)
               engine.reconcile(.granted) → start()
```

Revocation while running takes the same path in reverse. If the API reports
trust but a tap still will not attach — which happens after an app is replaced
on disk — the state becomes `.grantedButTapFailed` and the UI says so, rather
than claiming "granted" while nothing works.

## Recovery

| Event | Handling |
|---|---|
| `tapDisabledByTimeout` / `ByUserInput` | Re-enabled inside the callback; latch reset |
| Wake from sleep | `NSWorkspace.didWakeNotification` → verify and re-arm |
| Permission revoked | 1 Hz poll → `engine.stop()` |
| Permission granted | 1 Hz poll → `engine.start()` |
| Device connected / removed | Nothing to do — rules are per class, not per device |
| Settings changed | New snapshot pushed; no restart |
| Quit | Tap disabled, source removed, port invalidated, observers removed |

## Threading

| Thread | Work |
|---|---|
| Main | All UI, `AppState`, services, settings writes |
| `engineer.riteshrana.scrollwise.eventtap` | Tap callback only |
| — | No background queues; nothing else runs |

`SnapshotBox` (`OSAllocatedUnfairLock`) is the only shared mutable state, and it
is the only place the two threads meet.

## Entitlements

App Sandbox is **not** requested: a sandboxed process cannot hold the
Accessibility right an event tap requires. This is why every comparable input
utility ships unsandboxed with Developer ID rather than through the App Store.
Nothing else is requested — no network, no camera, no Input Monitoring, and file
access only to the app bundle the user explicitly picks in the Apps pane.

No private API is used anywhere.
