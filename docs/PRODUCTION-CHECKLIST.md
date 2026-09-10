# Production checklist

## Verdict — 2026-09-10 audit

**NOT PRODUCTION READY.** The engine, lifecycle and UI are now correct under
every condition this machine can reproduce, but the release gate has blockers
that no code change can clear: no Developer ID signature, no notarization, no
clean-machine install, and no pass over real hardware.

Status words: **PASS** — executed and passed. **PARTIAL** — part executed,
the rest listed. **MANUAL REQUIRED** — needs a person or hardware.
**BLOCKED** — this environment cannot do it. **NOT RUN** — could have, did not.

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
| Lifecycle | **PASS** | Single instance on the bundle; graceful quit leaves 0 processes, 0 taps |
| Sleep / wake | **MANUAL REQUIRED** | Wake handler PASS in TapCheck §2; a real sleep cycle not run |
| Login item | **PARTIAL** | State mapping PASS (Verify); registration verified in an earlier session; after reboot MANUAL REQUIRED |
| Shortcut | **PASS**, documented limit | ⌥⌘R toggles on the bundle; cross-process conflicts undetectable via `RegisterEventHotKey` |
| UI state truthfulness | **PASS** | Popover read via `AXUIElement`; "Reversing" only when something attached is reversed |
| Accessibility | **PARTIAL** | AX tree labelled; VoiceOver, Increase Contrast, Reduce Transparency/Motion MANUAL REQUIRED |
| Performance | **PASS** | Callback p99 1.62 µs; idle CPU 0.0–0.2 %; 47 MB RSS |
| Security | **PASS** | No `Process`, shell, `URLSession`, sockets or AppleScript; settings decoded defensively |
| Entitlements | **PASS** | Signed bundle carries only `apple-events = false`; no sandbox, network, camera, microphone or Input Monitoring |
| Code signing | **BLOCKED** | Local certificate only; `spctl` rejects the bundle. Needs Developer ID |
| Universal architecture | **PASS** / Intel hardware **BLOCKED** | `lipo`: x86_64 + arm64; the x86_64 Verify build passes under Rosetta; no Intel Mac available |
| Notarization | **BLOCKED** | Needs Developer ID. `notarytool` and `stapler` are present |
| Clean installation | **MANUAL REQUIRED** | Needs a machine that has never run Scrollwise |
| Upgrade | **PARTIAL** | The 0.0.1 store decodes to exactly what it held (Verify); the grant survives same-certificate rebuilds; a real N → N+1 install MANUAL REQUIRED |
| Uninstall | **NOT RUN** | Defined below |
| Documentation | **PASS** | Every document checked against the code and the runs above |

## Release blockers

1. **Developer ID Application certificate.** Accessibility grants are keyed to
   the designated requirement, so the identity must be settled before anyone
   installs the app — changing it later silently drops every user's grant.
2. **Notarization and stapling** of the DMG.
3. **Gatekeeper check on a clean machine**, downloaded the way a user would.
4. **The real-hardware input matrix** in TEST-PLAN.md, at minimum the built-in
   trackpad, a wheel mouse and a Magic Mouse.
5. **Start at login across a real reboot.**

## Commands

Validated in this audit:

```bash
swift build -c release
swift run -c release ScrollwiseVerify
swift run -c release ScrollwiseTapCheck
swift run -c release -Xswiftc -DSCROLLWISE_INSTRUMENT ScrollwiseTapCheck
bash Scripts/build-app.sh                 # universal, local identity
swift run -c release ScrollwiseTapCheck --running-app   # after: open build/Scrollwise.app
bash Scripts/make-dmg.sh
codesign --verify --strict --verbose=2 build/Scrollwise.app
spctl -a -vvv -t exec build/Scrollwise.app   # "rejected" until Developer ID + notarization
```

**Not validated** — no Developer ID exists on this machine. The shape is
standard; run it once and correct this section:

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" bash Scripts/build-app.sh
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" bash Scripts/make-dmg.sh
xcrun notarytool submit build/Scrollwise-0.0.1.dmg --keychain-profile <profile> --wait
xcrun stapler staple build/Scrollwise-0.0.1.dmg
spctl -a -vvv -t open --context context:primary-signature build/Scrollwise-0.0.1.dmg
```

`build-app.sh` adds `--timestamp` automatically for a Developer ID identity and
signs with the hardened runtime; the DMG script signs the image when
`SIGN_IDENTITY` is set.

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
next rebuild produces a different hash, stops matching, and the permission
silently stops applying **while the System Settings toggle still looks on**.
Re-toggling that stale entry cannot help; it has to be removed
(`tccutil reset Accessibility engineer.riteshrana.scrollwise`) and re-added.

Signing with a certificate yields `identifier "..." and certificate root =
H"..."` instead, which survives rebuilds. This audit rebuilt the bundle four
times and each launch was granted without re-approval. `Scripts/build-app.sh`
uses the identity when present and falls back to ad-hoc with a warning. The
recreation recipe is a comment at the signing block.

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

1. **Rules act on device *class*, not individual device.** No public API attaches
   a device identifier to a `CGEvent` scroll event. The Devices pane says so.
2. **A Magic Mouse follows the Trackpad rule.** Its scroll events carry the same
   gesture and momentum phases as a trackpad's. It is listed under Trackpad.
3. **The Tablet rule applies only if the tablet's driver marks its scroll events
   with a tablet subtype.** Unverified on hardware; a synthetic event cannot carry
   one.
4. **⌥⌘R is fixed, and a conflict with another app cannot be detected.**
   `RegisterEventHotKey` succeeds even when another process holds the same
   combination. A genuine registration failure is shown in the popover and the
   Shortcuts pane.
5. **Axis 3 and accelerated-delta fields are not flipped.** No evidence that any
   shipping device needs them.
6. **Momentum is latched per gesture, not per device.** A wheel click during
   trackpad inertia takes its own live decision and leaves the trackpad's alone.
7. **Switching the master switch off mid-flick lets that one gesture finish as it
   began.** Wheel clicks and the next gesture see the switch at once.
