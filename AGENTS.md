# Scrollwise — notes for coding agents

A macOS 26 menu bar utility that reverses scroll direction, with independent
rules per device class and per application. Everything about its shape follows
from one constraint: modifying an input event requires a `CGEventTap`, a tap
requires Accessibility, and Accessibility is a permission the user can refuse or
withdraw at any moment. The app therefore has to be honest about what it is
actually doing, and most of the rules below exist to keep it that way.

## Commands

```bash
swift build -c release                        # build everything
swift run -c release ScrollwiseVerify         # Core checks, no Xcode needed
swift run -c release ScrollwiseTapCheck       # live tap checks; needs Accessibility
swift run -c release -Xswiftc -DSCROLLWISE_INSTRUMENT ScrollwiseTapCheck  # + recovery, timing
swift run -c release ScrollwiseTapCheck --running-app   # end to end against a running bundle
bash Scripts/build-app.sh                     # universal, signed Scrollwise.app in build/
bash Scripts/make-dmg.sh                      # build/Scrollwise-<version>.dmg
swiftc -parse-as-library Scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
```

**`swift test` does not work on a Command Line Tools machine.** It fails with
`no such module 'Testing'`, because swift-testing ships with Xcode. This is not
a broken checkout. `ScrollwiseVerify` is a framework-free mirror asserting the
same things and is the one to run. `Tests/` holds the swift-testing version for
machines that do have Xcode; **keep the two in sync**, because on most machines
only one of them is ever executed. CI (`.github/workflows/ci.yml`, macOS 26 with
Xcode) runs both on every push, so a swift-testing failure shows up there even
when it cannot be reproduced locally.

**`ScrollwiseTapCheck` needs a trusted terminal and no running Scrollwise.** It
creates taps and posts scroll events, each stamped and consumed at the tail of
the session so no app scrolls. It refuses to run while Scrollwise is running,
because that tap would flip its events too. The instrumentation build stalls the
tap on purpose three times; real scrolling pauses for about 2.5 s each time.

## Architecture

Three modules, and the boundaries between them are the reason the project is
testable at all:

- **`ScrollwiseCore`** — every decision, no platform. It imports `Foundation` and
  `OSLog` and nothing else. `ScrollTransformer` (what to flip), `DeviceClassifier`
  (what produced the event), `RawScrollFields` (what the tap's integers mean),
  `GestureLatch` (momentum), `AccessibilityStatus` (permission transitions),
  `HIDPointingDeviceClassifier` (what a device is), `LoginItemState`, settings
  and persistence.
- **`ScrollwiseEngine`** — the tap and its owner: `EventTapController`,
  `ScrollEngine`, `SnapshotBox`, `CGEventScrollAccess`. A library so
  `ScrollwiseTapCheck` can drive exactly the code the app ships.
- **`ScrollwiseApp`** — the adapter. AppKit, SwiftUI, IOKit, Carbon,
  ServiceManagement. It reads the world, hands values to Core, and renders the
  answer.

**Put new decision logic in Core, not App.** Every bug found in this codebase so
far lived in App, in code with no test covering it, while Core — which is
exhaustively tested — had none. When you need to add behaviour, ask what part of
it is a pure function of its inputs, move that into Core, and leave App holding
only the framework calls.

Core must not gain a platform import. If a decision needs a framework type,
extract the values in App and pass primitives across.

## Invariants

1. **The UI never claims reversal is active when the tap cannot run.** If
   Accessibility is missing, controls stay settable and settings persist, but
   every surface says plainly that nothing is being changed. `AccessibilityStatus`
   is the single source of truth and every view reads it from there.
2. **Accessibility only — never Input Monitoring.** Device names come from IOKit
   properties, which are readable without opening the devices. Opening them, or
   calling `IOHIDManagerOpen`, is what raises the second, scarier prompt. Hot-plug
   callbacks fire from `IOHIDManagerScheduleWithRunLoop` alone; this is verified.
3. **No network, no analytics, no third-party dependencies.** The About pane and
   the README state this as fact, so it has to stay fact.
4. **No `TODO`, placeholder, mock or simulated state in shipped source.** If
   something cannot be implemented, say so in the UI in plain language — the
   Devices pane does this about per-device rules.

## Traps that have already cost time

**Writing a scroll delta field recomputes the others.** Setting
`scrollWheelEventDeltaAxis1` makes CoreGraphics rewrite the pixel and
fixed-point fields from it. Read all three, then write all three — negating each
field just after writing the previous one flips the recomputed values back, and
apps reading `scrollingDeltaY` see the original direction. The live check
(`ScrollwiseTapCheck`, section 3) compares all six fields and fails on this.

**`tapDisabledByTimeout` cannot be relied on to arrive.** Measured on macOS
26.5: a callback stalled past the timeout got its tap disabled, and no disabled
notification ever reached the callback. The watchdog timer on the tap thread is
what re-enables it. Do not remove it because the callback path "handles" this.

**A synthetic scroll event cannot carry a tablet subtype.** The subtype set on a
posted scroll event arrives at the tap as 0, so the Tablet rule is unreachable
from any automated test. It needs a real tablet.

**`RegisterEventHotKey` does not fail when another process holds the same
combination.** Both registrations return `noErr`. The UI's "in use elsewhere"
state covers genuine registration failures only; a cross-process conflict is
not detectable through this API.

**In zsh, `log` is a builtin.** `log stream …` fails with "too many arguments";
call `/usr/bin/log`. And macOS's `xattr` has no `-r`; walk the tree with `find`.

**Ad-hoc signing silently revokes Accessibility.** `codesign --sign -` produces a
designated requirement of `cdhash H"..."` — a hash of one exact build — so every
rebuild stops matching the stored TCC record and the permission quietly stops
applying *while the System Settings switch still looks on*. The build script signs
with a stable certificate ("Scrollwise Local Signing") to avoid this. If a grant
ever breaks, re-toggling the stale entry cannot fix it:
`tccutil reset Accessibility engineer.riteshrana.scrollwise`, then re-add.

**A Terminal-launched build reports permission falsely.** Running
`Scrollwise.app/Contents/MacOS/ScrollwiseApp` directly makes the app inherit
*Terminal's* Accessibility grant through TCC responsible-process attribution, so
it shows "Accessibility granted" when the bundle has none. Only `open <bundle>`
reports the real state. Never conclude anything about permissions from a
Terminal launch.

**HID device class comes from usage *pairs*, never primary usage.** A trackpad's
first collection is `GenericDesktop/Mouse` — the built-in MacBook trackpad reports
primary usage `(1,2)` — so primary usage alone calls every trackpad a mouse. The
`(13,5)` `Digitizer/TouchPad` entry in `kIOHIDDeviceUsagePairsKey` is the only
thing that separates them. Related: `kIOHIDDeviceUsagePageKey` and
`kIOHIDDeviceUsageKey` are *matching* keys and read back `nil` as device
properties; the readable ones are `kIOHIDPrimaryUsagePageKey` / `…UsageKey`.
And `IOHIDManagerCopyDevices` returns a device once per matched criterion, so one
trackpad arrives twice — deduplicate on `kIOHIDUniqueIDKey`.

**`SMAppService.mainApp.status` returns `.notFound` for an app that has simply
never been registered**, not `.notRegistered`. It is not a refusal: `register()`
from that state succeeds. Only a thrown error is evidence the system refused.

**A default that disables the only control able to change it is a dead end.**
This shipped twice — the login-item gate above, and a tablet `DeviceRule` with
`isEnabled: false` that no UI could ever set back. When a control is gated on
state, ask what writes that state; if the only writer is the gated control, the
design is broken. Gate on an observed failure, never on an initial value.

**Never stack `.opacity()` on an already-dimmed semantic style.** `.tertiary` at
50% opacity measured **1.33:1** in light mode. Dim by moving `.primary` to
`.secondary`, not by multiplying. Reserve `.tertiary` for decoration such as
chevrons — never for prose or a status word the user has to read.

## Decided, with evidence — do not silently revert

- **`.glassEffect` is not used anywhere, deliberately.** It was applied once to a
  tile whose own fill is opaque, so the material was completely covered: measured
  pixel-identical to deleting the modifier. Glass here comes from the system
  materials — `MenuBarExtra(.window)` and `NavigationSplitView` — which is what
  macOS actually does.
- **The settings sidebar is opaque, and that is correct.** Measured against
  Apple's own System Settings on the same backdrop: theirs is flat at sd 0.57,
  ours 0.89. An earlier "fix" that made it translucent moved it 15 luminance
  units *away* from native and was reverted. Measure the platform before
  concluding the platform is being missed.
- **SF Symbols may be used in the UI but not in the app icon.** Apple's licence
  prohibits the latter, which is why `Scripts/make-icon.swift` draws the arrows
  as Bézier strokes while the interface uses `arrow.up.arrow.down`.
- **Rules act on device *class*, not individual device.** No public API attaches a
  device identifier to a `CGEvent` scroll event. The Devices pane says so rather
  than shipping per-device switches that secretly move together.

- **Releases are self-signed with "Scrollwise Local Signing" and not notarized.**
  The project does not pay for the Apple Developer Program. That certificate is
  the release identity: users' Accessibility grants are tied to its root hash, so
  never sign a release ad hoc or with another certificate — `make-dmg.sh`
  refuses to. Replacing it is a breaking release (every user re-grants once).
  Details, fingerprint and backup steps: `docs/PRODUCTION-CHECKLIST.md`.

## Verifying UI work

Claims about appearance need measurement, not assertion.

- **Contrast**: composite the text colour over its real background and compute the
  WCAG ratio. Beware measuring from a screenshot: a downscaled or JPEG-compressed
  capture blends glyph edges and *understates* small text — a control measurement
  on known 14:1 text read 9–12:1 on the same image. Verify the instrument before
  trusting a surprising number.
- **Accessibility tree**: read it with `AXUIElement` directly. AppleScript's
  System Events returns nothing useful for these SwiftUI windows and will make you
  think the tree is empty when it is fine.
- **Behaviour**: the app logs to subsystem `engineer.riteshrana.scrollwise`. Use
  `log stream --predicate 'subsystem == "engineer.riteshrana.scrollwise"' --info`;
  `log show` frequently returns nothing for these info-level entries. Note that
  `os_log` redacts interpolations by default — add `privacy: .public` for values
  that are not sensitive, or the line reads `<private>` and tells you nothing.

## Docs

`docs/ARCHITECTURE.md` (layers, threading, recovery) · `docs/TEST-PLAN.md`
(automated coverage and the manual matrix, including what is still unverified) ·
`docs/PRODUCTION-CHECKLIST.md` (signing, notarization, known limitations) ·
`docs/FRONTEND-AUDIT.md` (the design canvas, the glass findings, control mapping).

Keep them honest. Several entries record things that turned out to be **wrong**
and were corrected; that history is worth more than a tidy document.
