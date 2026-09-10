# Scrollwise

[![CI](https://github.com/riteshr19/Scrollwise/actions/workflows/ci.yml/badge.svg)](https://github.com/riteshr19/Scrollwise/actions/workflows/ci.yml)

Reverses the direction of scrolling on macOS, with independent settings for
trackpads and mice. Menu bar utility, macOS 26+, Apple silicon and Intel.

Rules act on the *kind* of device, recognised from how it scrolls: a Magic Mouse
scrolls with trackpad gestures, so the Trackpad rule governs it.

**Status: not yet released.** Releases will be signed with the project's own
certificate rather than notarized by Apple — see [Install](#install). What must
pass before the first release is listed in
[docs/PRODUCTION-CHECKLIST.md](docs/PRODUCTION-CHECKLIST.md).

Built from a design canvas exploring four architectures — this implements
option **1b** (sidebar + detail settings window) and option **1d** (menu bar
popover), which are complementary rather than alternatives. The canvas is not
part of this repository; `docs/FRONTEND-AUDIT.md` records what it contained and
how each control maps to a native surface.

## Screenshots

The menu bar popover — everything reachable without opening a window.

<img src="docs/images/popover.png" width="340" alt="Scrollwise menu bar popover: a Reversing header with a master switch, a Devices list naming the attached hardware, per-app and login rows, and the ⌥⌘R shortcut in the footer.">

The Scrolling pane. "Right now" reports what the engine is actually doing rather
than what the settings hope it is doing.

<img src="docs/images/scrolling.png" width="820" alt="Scrollwise Scrolling settings pane in dark mode, showing the Reverse scrolling master switch, vertical and horizontal axis toggles, and an Engine row reading Running, attached to the scroll event stream.">

Devices, listing the real hardware under the rule that governs it. macOS does not
tell an app which individual mouse produced a scroll, so rules act on the device
*class* — the pane says so rather than faking per-device switches.

<img src="docs/images/devices.png" width="820" alt="Scrollwise Devices settings pane, with Trackpad, Mouse and Tablet groups. The trackpad group lists Apple Internal Keyboard / Trackpad, Built-in, marked Covered. The mouse and tablet groups read Nothing of this kind is connected.">

Light mode. Every colour is semantic, so appearance, Increase Contrast and
Reduce Transparency are handled by the system rather than by hand.

<img src="docs/images/scrolling-light.png" width="820" alt="The same Scrolling pane in light mode, showing the app adapts to the system appearance.">

About.

<img src="docs/images/about.png" width="820" alt="Scrollwise About pane, showing version, author and contact, repository and licence links, and a privacy summary: no network access, no analytics, scroll events read only to reverse them, no third-party code.">

## Install

Scrollwise is free and open source, and it is **not notarized by Apple** —
notarization requires a paid Apple developer membership. Each release is signed
with the project's own certificate instead, so macOS asks you to confirm it once
for each download.

1. Download `Scrollwise-<version>.dmg` from
   [Releases](https://github.com/riteshr19/Scrollwise/releases).
2. Optionally, check it against the SHA-256 published with the release:
   `shasum -a 256 ~/Downloads/Scrollwise-<version>.dmg`
3. Open the disk image and drag **Scrollwise** into **Applications**.
4. Open Scrollwise. macOS says it cannot verify the app — click **Done**.
5. Open **System Settings › Privacy & Security**, scroll down to the message
   about Scrollwise, click **Open Anyway**, and confirm. From Terminal instead:
   `xattr -dr com.apple.quarantine /Applications/Scrollwise.app`
6. Grant **Accessibility** when Scrollwise asks (System Settings › Privacy &
   Security › Accessibility). It notices within about a second; no restart.

**Updating:** quit Scrollwise, replace it in Applications with the new version,
and repeat steps 4–5 once. Accessibility stays granted, because every release is
signed with the same certificate.

**Rather not run a downloaded app?** Build it yourself, below. It needs only
Apple's free Command Line Tools, and an app you build locally is not blocked by
Gatekeeper at all.

## Build and run

```bash
xcode-select --install             # once, if the Command Line Tools are missing
bash Scripts/build-app.sh          # → build/Scrollwise.app, universal (arm64 + x86_64)
open build/Scrollwise.app
bash Scripts/make-dmg.sh           # → build/Scrollwise-<version>.dmg and .sha256
```

Launch it with `open`, not by running the binary: a Terminal launch inherits
Terminal's Accessibility grant and reports permission that the app does not have.

Without a signing certificate of your own, the build is signed ad hoc, and macOS
treats every rebuild as a different app: Accessibility has to be removed and
granted again after each one. The comment at the signing step of
`Scripts/build-app.sh` shows how to make a local certificate that avoids this.

Then grant Accessibility access: **System Settings › Privacy & Security ›
Accessibility**. The app opens its window on first launch to explain why, and
picks up the change within about a second — no restart.

Until access is granted the engine stays stopped and the interface says so.
Nothing pretends to work.

## Verify

```bash
swift run -c release ScrollwiseVerify     # 140 checks of the decision layer, no Xcode required
swift run -c release ScrollwiseTapCheck   # 44 checks against the real event tap; needs Accessibility
swift run -c release -Xswiftc -DSCROLLWISE_INSTRUMENT ScrollwiseTapCheck   # 56, adds recovery and timing
swift run -c release ScrollwiseTapCheck --running-app   # 6, end to end against the running app
swift test                                # the swift-testing suite; needs Xcode for `Testing`
```

CI (`.github/workflows/ci.yml`) runs the build, `ScrollwiseVerify`, `swift test`
and the universal bundle build on macOS 26 with Xcode for every push.

`ScrollwiseTapCheck` posts scroll events and consumes them before any app sees
them, and refuses to run while Scrollwise itself is running. What each suite
covers, and what still needs a hand on real hardware, is in
[docs/TEST-PLAN.md](docs/TEST-PLAN.md).

## Layout

```
Sources/ScrollwiseCore/     pure logic — no AppKit, no CoreGraphics
  Model/                        settings, rules, deltas, raw event fields, permission state
  Classification/               event traits → device class; HID devices
  Transform/                    flip decision + momentum latch
  Settings/                     lenient persistence and shipped defaults
Sources/ScrollwiseEngine/   event tap, its thread and watchdog, the engine that owns it
Sources/ScrollwiseApp/      the application
  Services/                     accessibility, login item, HID, shortcut
  UI/MenuBar/                   option 1d
  UI/Settings/                  option 1b
Sources/ScrollwiseVerify/   framework-free checks of Core
Sources/ScrollwiseTapCheck/ live checks against the real tap (dev tool, not shipped)
Tests/                          swift-testing suite
Scripts/                        universal build + signing, DMG, icon
docs/                           architecture, audit, test plan, checklist
```

## Contributing

`AGENTS.md` holds the working notes for this repository — commands, the module
boundary, the invariants, and the traps that have already cost time (TCC and code
signing, HID device classification, `SMAppService` status). Coding agents read it
automatically; it is worth a human read too. `CLAUDE.md` imports it so there is
one file to maintain.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers, event pipeline, threading, permissions, recovery
- [docs/FRONTEND-AUDIT.md](docs/FRONTEND-AUDIT.md) — what the canvas contained, the glass finding, control mapping
- [docs/TEST-PLAN.md](docs/TEST-PLAN.md) — automated coverage and the manual matrix
- [docs/PRODUCTION-CHECKLIST.md](docs/PRODUCTION-CHECKLIST.md) — release gate, release identity, known limitations

## Notes

- **Not sandboxed.** A sandboxed process cannot hold the Accessibility right an
  event tap needs, so Scrollwise cannot be in the App Store. It is distributed as
  a self-signed disk image on GitHub.
- **Not notarized.** Notarization needs a paid Apple developer membership. The
  cost to you is one confirmation per download (see [Install](#install)); the
  source, the build script and a checksum for every release are here to check.
- **No third-party dependencies.** AppKit, SwiftUI, CoreGraphics, IOKit,
  ServiceManagement, Carbon (for the global hot key), OSLog.
- **No private API.**

## Author

Ritesh Rana — <contact@riteshrana.engineer>

## Licence

MIT. See [LICENSE](LICENSE).

## Privacy

Scrollwise links no networking code, requests no network entitlement, and has no
third-party dependencies. It reads scroll events in order to reverse them and
inspects nothing else — not keystrokes, not clicks, not pointer movement. The
event tap's mask is `scrollWheel` only, so its callback is never consulted for
any other kind of input. Nothing is collected, stored off-device, or sent.

Scrollwise needs Accessibility access because modifying an input event requires
it. It deliberately does **not** ask for Input Monitoring: device names come from
IOKit properties, which can be read without opening the devices.
