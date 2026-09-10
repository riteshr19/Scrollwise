# Production checklist

## Verdict — 2026-09-10 audit

**NOT PRODUCTION READY — yet.** The engine, lifecycle and UI are correct under
every condition this machine can reproduce, and distribution is settled:
self-signed, not notarized, as a documented limitation. What remains is testing
that only people and other hardware can do — a second Mac, real input devices,
a real reboot. When those pass, the verdict becomes **READY WITH DOCUMENTED
LIMITATIONS**.

Status words: **PASS** — executed and passed. **PARTIAL** — part executed,
the rest listed. **MANUAL REQUIRED** — needs a person or hardware.
**BLOCKED** — this environment cannot do it. **NOT RUN** — could have, did not.
**LIMITATION** — deliberately not done; documented for users.

## Distribution decision

Scrollwise is open source and free, and the project does not pay for the Apple
Developer Program. So:

- **Releases are signed with the project's self-signed release identity**,
  "Scrollwise Local Signing" (below). Not ad hoc: an ad-hoc signature is a
  different identity every build, so each update would silently break every
  user's Accessibility grant.
- **Releases are not notarized.** Notarization requires a Developer ID
  signature, which requires the paid membership. Gatekeeper therefore asks each
  user to confirm each download once (System Settings › Privacy & Security ›
  Open Anyway). The README's Install section walks through it.
- **Trust without Apple** comes from the published source, the build script,
  and a SHA-256 for every disk image (`make-dmg.sh` writes it). Anyone can build
  from source with the free Command Line Tools; a local build is never
  quarantined.

## Release gate

| Category | Status | Evidence |
|---|---|---|
| Event correctness | **PASS** (synthetic) | TapCheck §3: all six delta fields negated in what an app receives. Fixed a critical defect where only the line field was |
| Device classification | **PASS**, documented limits | Verify; Magic Mouse follows the Trackpad rule and is listed there; tablet path MANUAL REQUIRED |
| Gesture / momentum | **PASS** (synthetic) | TapCheck §4 on the live tap; real feel MANUAL REQUIRED |
| Settings atomicity | **PASS** | Whole-value swap in `SnapshotBox`; lenient decode, normalization, backup (Verify) |
| Permission lifecycle | **PARTIAL** | Granted and untrusted/replaced launches PASS on the bundle; revoke-while-running MANUAL REQUIRED |
| Event-tap recovery | **PASS** | Watchdog re-enabled a timed-out tap 3 of 3 times; the callback notification never arrived |
| Thread safety | **PASS** | Review of every shared field; 200 start/stop races, 0 leaked taps |
| Lifecycle | **PASS** | Single-instance `flock`; two simultaneous launches leave one; graceful quit leaves 0 processes, 0 taps |
| Sleep / wake | **MANUAL REQUIRED** | Wake handler PASS in TapCheck §2; a real sleep cycle not run |
| Login item | **PARTIAL** | State mapping PASS (Verify); registration verified in an earlier session; after reboot MANUAL REQUIRED |
| Shortcut | **PASS**, documented limit | ⌥⌘R toggles on the bundle; cross-process conflicts undetectable via `RegisterEventHotKey` |
| UI state truthfulness | **PASS** | Popover read via `AXUIElement`; "Reversing" only when something attached is reversed |
| Accessibility | **PARTIAL** | AX tree labelled; VoiceOver, Increase Contrast, Reduce Transparency/Motion MANUAL REQUIRED |
| Performance | **PASS** | Callback p99 1.62 µs; idle CPU 0.0–0.2 %; 47 MB RSS |
| Security | **PASS** | No `Process`, shell, `URLSession`, sockets or AppleScript; settings decoded defensively |
| Entitlements | **PASS** | Signed bundle carries only `apple-events = false`; no sandbox, network, camera, microphone or Input Monitoring |
| Code signing | **PASS**, documented limit | Every release signed with the release identity; `make-dmg.sh` refuses anything else. Gatekeeper rejects it until the user confirms once — LIMITATION |
| Universal architecture | **PASS** / Intel hardware **BLOCKED** | `lipo`: x86_64 + arm64; the x86_64 Verify build passes under Rosetta; no Intel Mac available |
| Notarization | **LIMITATION** | Not pursued: requires the paid Apple Developer Program |
| Clean installation | **MANUAL REQUIRED** | Second Mac: download, Open Anyway, grant, scroll |
| Upgrade | **PARTIAL** | The 0.0.1 store decodes to exactly what it held (Verify); the grant survives same-certificate rebuilds on this Mac; across a real download-and-replace on another Mac MANUAL REQUIRED |
| Uninstall | **NOT RUN** | Defined below |
| Documentation | **PASS** | Every document checked against the code and the runs above |

## Before the first release

1. **Clean-machine install on a second Mac** (or a fresh user account that has
   never run Scrollwise): download the DMG in Safari, check the checksum, drag
   to Applications, Open Anyway, grant Accessibility, confirm scrolling reverses.
2. **Update on that Mac.** Build a second version (bump `CFBundleVersion`),
   install it over the first, and confirm Accessibility is *still granted* and
   working with no re-grant. This is the one assumption behind self-signed
   distribution that has not been tested off this machine: it holds here across
   every rebuild, and nothing in the mechanism depends on the certificate being
   trusted, but it has to be seen on a second Mac.
3. **The real-hardware input matrix** in TEST-PLAN.md — at minimum the built-in
   trackpad, a wheel mouse and a Magic Mouse.
4. **Start at login across a real reboot.**

## Release identity

| | |
|---|---|
| Name | Scrollwise Local Signing |
| Kind | Self-signed code-signing certificate, RSA 2048 |
| Valid | 2026-09-10 → **2036-09-07** |
| SHA-1 | `AF42092504793D595007B9FD5EB04B86D07CB934` — the `certificate root` hash in every release's designated requirement |
| Private key | This Mac's login keychain only. Never in the repository |

**Back up the private key now.** Keychain Access › login › My Certificates ›
"Scrollwise Local Signing" › File › Export Items… › save as `.p12` with a strong
password, and keep it offline. Restore on a new build machine by double-clicking
the `.p12`. If the key is lost, the next release has to use a new certificate and
every user re-grants Accessibility once.

**Replacing it is a breaking release.** Any other certificate — including a
re-issued one with the same name — has a different root hash. Do it only
deliberately, say so in the release notes, and plan it well before 2036-09-07.
What macOS does with an expired self-signed release identity has not been tested.

## Commands

Validated in this audit:

```bash
swift build -c release
swift run -c release ScrollwiseVerify
swift run -c release ScrollwiseTapCheck
swift run -c release -Xswiftc -DSCROLLWISE_INSTRUMENT ScrollwiseTapCheck
bash Scripts/build-app.sh                 # universal, signed with the release identity
swift run -c release ScrollwiseTapCheck --running-app   # after: open build/Scrollwise.app
bash Scripts/make-dmg.sh                  # DMG + .sha256; refuses a non-release signature
shasum -a 256 -c build/Scrollwise-0.0.1.dmg.sha256      # run inside build/
codesign --verify --strict --verbose=2 build/Scrollwise.app
spctl -a -vvv -t exec build/Scrollwise.app   # "rejected": expected without notarization
```

Not validated — publishing is the maintainer's call:

```bash
gh release create v0.0.1 build/Scrollwise-0.0.1.dmg build/Scrollwise-0.0.1.dmg.sha256 \
    --title "Scrollwise 0.0.1" --notes "SHA-256: <from the .sha256 file>"
```

### If the project ever joins the Apple Developer Program

Also not validated. Moving to Developer ID changes the release identity, so the
first Developer ID release makes every user re-grant Accessibility once.

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" bash Scripts/build-app.sh
ditto -c -k --keepParent build/Scrollwise.app build/Scrollwise.zip
xcrun notarytool submit build/Scrollwise.zip --keychain-profile <profile> --wait
xcrun stapler staple build/Scrollwise.app
RELEASE_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
    SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" bash Scripts/make-dmg.sh
xcrun notarytool submit build/Scrollwise-0.0.1.dmg --keychain-profile <profile> --wait
xcrun stapler staple build/Scrollwise-0.0.1.dmg
```

## Uninstall

What uninstalling means, so it can be tested:

1. Quit Scrollwise (popover › Quit). No process or tap remains — verified.
2. Turn off Start at login first, or remove it afterwards in System Settings ›
   General › Login Items.
3. Drag Scrollwise.app to the Trash.
4. Remove it from System Settings › Privacy & Security › Accessibility, or
   `tccutil reset Accessibility engineer.riteshrana.scrollwise`.
5. Settings stay in `~/Library/Preferences/engineer.riteshrana.scrollwise.plist`
   and are not deleted automatically; `defaults delete engineer.riteshrana.scrollwise`
   removes them.

Not yet run end to end.

## Why the signing identity is not ad-hoc

An ad-hoc signature (`--sign -`) carries no certificate, so the designated
requirement macOS derives from it is `cdhash H"..."` — the hash of one exact
build. TCC stores that requirement when the user grants Accessibility, so the
next build produces a different hash, stops matching, and the permission
silently stops applying **while the System Settings toggle still looks on**.
Re-toggling that stale entry cannot help; it has to be removed
(`tccutil reset Accessibility engineer.riteshrana.scrollwise`) and re-added.

Signing with a certificate yields `identifier "..." and certificate root =
H"..."` instead, which survives rebuilds. This audit rebuilt the bundle many
times and each launch was granted without re-approval. The audit also launched
an ad-hoc re-signed copy: macOS reported it untrusted and the app said so.

Two related traps:

- Launching the binary directly from Terminal makes the app inherit **Terminal's**
  Accessibility grant through TCC responsible-process attribution, so it reports
  "Accessibility granted" when the bundle has none. Only `open <bundle>` reports
  the real state.
- `SMAppService.mainApp.status` returns `.notFound` for an app that has never
  been registered, not `.notRegistered`. It is not a refusal — see
  `LoginItemState`.

## Migration note

An early build shipped the tablet rule with `isEnabled: false`, which no control
can change. Checked on the one store that exists — this machine's — and it holds
the rule enabled. There are no released users, so no migration was written. The
decoder is now field-by-field lenient, so adding a field no longer resets stored
settings, and `schemaVersion` marks where the first non-additive change goes.

## Known limitations, deliberate

1. **Not notarized.** Each download needs one Open Anyway confirmation. Updates
   keep Accessibility because the release identity never changes.
2. **Rules act on device *class*, not individual device.** No public API attaches
   a device identifier to a `CGEvent` scroll event. The Devices pane says so.
3. **A Magic Mouse follows the Trackpad rule.** Its scroll events carry the same
   gesture and momentum phases as a trackpad's. It is listed under Trackpad.
4. **The Tablet rule applies only if the tablet's driver marks its scroll events
   with a tablet subtype.** Unverified on hardware; a synthetic event cannot carry
   one.
5. **⌥⌘R is fixed, and a conflict with another app cannot be detected.**
   `RegisterEventHotKey` succeeds even when another process holds the same
   combination. A genuine registration failure is shown in the popover and the
   Shortcuts pane.
6. **Axis 3 and accelerated-delta fields are not flipped.** No evidence that any
   shipping device needs them.
7. **Momentum is latched per gesture, not per device.** A wheel click during
   trackpad inertia takes its own live decision and leaves the trackpad's alone.
8. **Switching the master switch off mid-flick lets that one gesture finish as it
   began.** Wheel clicks and the next gesture see the switch at once.
