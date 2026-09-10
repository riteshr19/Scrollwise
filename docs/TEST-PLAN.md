# Test plan

## Automated

`Tests/ScrollwiseCoreTests` — swift-testing, across seven suites. Every
suite added after the first round exists because a real defect shipped through
that gap: the classification, transport, identity and login-item suites each pin
a bug that reached a running build.
Because the decision layer has no CoreGraphics dependency, every rule is checked
without synthesising a single physical scroll event.

| Suite | Covers |
|---|---|
| `ScrollTransformerTests` | device independence, master switch, disabled rules, unknown→mouse fallback, horizontal opt-in, app-rule precedence, disabled app rules, forceReverse, all-three-representation negation, involution |
| `DeviceClassifierTests` | trackpad gesture, momentum, discrete wheel, high-resolution wheel, tablet priority |
| `GestureLatchTests` | momentum inheritance, discrete non-latching, reset |
| `SettingsTests` | shipped defaults, every shipped rule reachable, immutability, persistence round trip, corruption fallback, empty store |
| `HIDPointingDeviceClassifierTests` | built-in trackpad despite primary usage Mouse, touch pad over mouse, pen and bare digitizer as tablet, primary-usage fallback, empty fallback |
| `HIDTransportTests` | FIFO and SPI as internal, every Bluetooth spelling, USB, unknown transport passed through |
| `HIDIdentityTests` | two references to one device collapse, two identical mice stay separate, serial fallback, empty serial ignored, location fallback |
| `LoginItemStateTests` | never-registered is offerable, awaiting approval reads as on, enabled, explicitly unregistered |

### Running them

`swift test` requires the `Testing` module, which ships with **Xcode**, not
Command Line Tools. On a machine with only CLT installed, run the mirror target
instead — same assertions, no framework:

```
swift run ScrollwiseVerify     # → "PASS — 34 checks"
```

Status on the build machine: `ScrollwiseVerify` **passes, 73/73**.
`swift test` was **not** run — no Xcode present.

## Manual — input matrix

Requires Accessibility granted. For each cell, confirm direction is correct and
that motion is smooth with no jitter, stutter or direction snap.

| | trackpad | wheel mouse | high-res wheel | Magic Mouse |
|---|---|---|---|---|
| slow vertical | | | | |
| fast vertical | | | | |
| single click/tick | n/a | | | n/a |
| horizontal | | | | |
| momentum / flick | | n/a | n/a | |
| rapid direction change | | | | |
| setting changed mid-flick | must **not** reverse in-flight inertia | n/a | n/a | same |

## End-to-end event verification

Direction correctness is checked against the live tap rather than reasoned about.
A listen-only tap is placed at the **tail** of the session chain, so it observes
events after Scrollwise's head-inserted tap has modified them; a synthetic scroll
is posted at the HID level and the delivered delta read back.

| posted | classified | rule | observed | |
|---|---|---|---|---|
| `+3`, discrete, no phase | mouse | reverse | **−3** | reversed |
| `+3`, continuous + phase | trackpad | leave alone | **+3** | untouched |

That single pair exercises the whole path: the tap is attached and modifying, the
classifier separates the device classes from event traits alone, and the per-class
rules are applied. It does **not** cover feel — smoothness, jitter and direction
snap still need a hand on real hardware, which is what the matrix above is for.

Reproduce with a tap created as
`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, …)`.

## Manual — untouched input

Confirm none of these change while the engine is running: cursor movement, left
/ right / middle click, drag, keyboard input, pinch-zoom, rotate, swipe between
pages, Mission Control gestures, app shortcuts. The tap's mask is `scrollWheel`
only, so the callback is never consulted for any of them.

## Manual — lifecycle

- [x] First launch with no permission → window explains, engine stays stopped, no
      control claims success *(verified: `Scroll engine stopped`, no tap installed,
      no system prompt, settings window opened itself, banner and footer both honest)*
- [x] Grant permission with app running → engine starts, no restart *(verified:
      the app was already running as pid 67554 when the grant was made and picked
      it up on its own — same process, engine attached, no relaunch)*
- [ ] Revoke permission with app running → engine stops, UI reports it.
      **Not verifiable with `tccutil reset`**: clearing the TCC entry leaves an
      already-running process trusted — the app polls `AXIsProcessTrusted()` every
      second and kept reporting granted, because tccd still answered "trusted" for
      that pid. Needs the switch unticked by hand while the app runs.
- [ ] Sleep → wake → scrolling still reversed
- [x] Quit → no process remains *(verified: "Application shut down cleanly", 0 processes)*
- [x] Start at login on → registers; macOS lists it under Login Items *(verified:
      `notRegistered` → `enabled` round trip through the UI)*
- [ ] Start at login on → reboot → app present in menu bar, engine running
- [ ] Revoke login item in System Settings → app's switch corrects itself on next launch
- [x] ⌥⌘R from another app toggles reversal *(verified with Finder frontmost:
      persisted `isEnabled` went true → false → true across two presses)*
- [ ] Connect/disconnect a Bluetooth mouse mid-session → rules keep working, and
      the device list updates without reopening the popover *(hot-plug callbacks
      verified to fire without `IOHIDManagerOpen`, so no Input Monitoring prompt;
      the add/remove event itself still needs hardware)*
- [ ] Replace the .app on disk → `.grantedButTapFailed` path shows the real message

## Appearance and accessibility

- [x] Light mode — every pane and the popover reviewed
- [x] Contrast measured. The popover's disabled device rows stacked `.opacity(0.5)`
      on an already-dimmed `.tertiary` style and measured **1.33:1**; they now use
      a semantic style alone at **3.81:1**. `.tertiary` prose in the Devices pane
      was lifted to `.secondary` for the same reason.
- [x] Accessibility tree audited via `AXUIElement`. Every control the app owns
      carries a label; the unlabeled elements are sidebar rows (which carry their
      text inside, as outline views do) and system scrollbar/window chrome. Fixed
      along the way: the direction pickers announced "Scroll direction, Scroll
      direction" — duplicated, and identical for all three device classes — and
      the "Start at login" switch reached VoiceOver with no label at all.
- [ ] **Increase Contrast — not tested.** `com.apple.universalaccess` is
      TCC-protected, so the setting could not be toggled from a script. Needs a
      manual pass.
- [ ] VoiceOver heard end to end by a person. The tree is correct; nobody has
      listened to it.

## Performance

| Metric | Method | Result |
|---|---|---|
| Idle CPU | `ps -o %cpu` over 5 s | **0.0–0.3 %** |
| Idle memory | `ps -o rss` | **~96 MB RSS** (SwiftUI/AppKit baseline) |
| Threads | `ps -M` | 5, one of which is the tap |
| Crash-free launch | DiagnosticReports | **no reports** |
| Callback duration | see below | not yet measured |
| Input latency | see below | not yet measured |

### Measuring the callback

Not yet instrumented. The intended method, kept out of the shipping build:

```swift
#if SCROLLWISE_INSTRUMENT
let signpost = OSSignposter(logger: Log.tap)
let id = signpost.makeSignpostID()
let interval = signpost.beginInterval("scroll", id: id)
defer { signpost.endInterval("scroll", interval) }
#endif
```

Then profile under Instruments' os_signpost track while scrolling continuously,
and check the distribution stays well inside the tap timeout. Guarded by a
compile flag so no signpost cost exists in release, per §33.
