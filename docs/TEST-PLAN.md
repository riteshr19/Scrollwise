# Test plan

Status words mean exactly this: **PASSED** — executed, and it passed.
**NOT RUN** — could have run but did not. **BLOCKED** — this environment cannot
run it. **MANUAL REQUIRED** — needs a person or hardware; cannot be automated.

Last full run: 2026-09-10, macOS 26.5.1 (25F80), Apple silicon (arm64), Swift
6.2.4, Command Line Tools only — no Xcode.

## Automated

| Suite | What it drives | Count | Status |
|---|---|---|---|
| `ScrollwiseVerify` | Core, framework-free | 140 checks | **PASSED** — native arm64, and the x86_64 build under Rosetta |
| `ScrollwiseCoreTests` | Core, swift-testing | 63 tests in 15 suites | **BLOCKED** — needs Xcode's `Testing` module |
| `ScrollwiseTapCheck` | the real event tap | 44 checks | **PASSED** (3 not run: tablet, recovery, timing) |
| `ScrollwiseTapCheck`, instrumented | + timeout recovery, callback timing | 56 checks | **PASSED** (1 not run: tablet) |
| `ScrollwiseTapCheck --running-app` | the built, signed, running bundle | 6 checks | **PASSED** |

### Why the counts used to disagree

Earlier documents said both "34 checks" and "73/73". Both were true at different
times: 34 was `ScrollwiseVerify` before the HID, transport, identity and
login-item sections were added; 73 was its count at commit `a7db45a`, confirmed
by running it at the start of this audit. The README and this file were not
updated together. Now: 140 Verify checks mirror the 63 swift-testing tests
(several `#expect`s per test, one `expect` per assertion), and the two are kept in
sync by hand because on most machines only one of them runs.

### ScrollwiseVerify and ScrollwiseCoreTests

Transformer (device independence, master switch, precedence under conflicting
app rules, forceReverse, forceNatural) · delta arithmetic, including `Int64.min`
· classification from traits and from raw fields · the latch across a whole flick
with a mid-gesture setting change · raw phase mapping, including that
scroll-phase *ended* does not end the gesture · settings defaults, round trip,
lenient decoding of missing fields and unknown actions, lossy arrays,
normalization, `activeProfile` with no profiles, the exact 0.0.1 store format,
backup of unreadable data · Accessibility status transitions, including sticky
tap failure · HID classification (pen over
touch pad, Magic Mouse), transports, identity · login-item state mapping.

### ScrollwiseTapCheck

Every event it posts is stamped in `eventSourceUserData` and consumed by a tap at
the tail of the session, after the engine's head-inserted tap has changed it — so
it reads what an app would receive, and nothing on screen scrolls.

1. **One controller, one tap** — installed is reported; exactly one tap
   (`CGGetEventTapList`); mask is scroll wheel only; a second `start()` adds
   nothing; `stop()` returns with the tap gone; a stopped controller cannot
   restart; **200 stops racing their starts leave 0 taps, peak 1**.
2. **Engine lifecycle** — `.starting` before `.running`; two starts make one tap;
   wake re-arms without adding one; stop/start leaves exactly one; **100 rapid
   cycles leave 0 and late reports from replaced taps are ignored**; tap-failure
   status does not tear down a working tap; losing permission removes the tap;
   no trust, no attempt.
3. **End-to-end direction** — wheel click reversed in all six fields; trackpad
   left natural; horizontal only when opted in; master switch off; passthrough
   app rule for its app only.
4. **Gesture latch on the live tap** — mid-gesture setting change; the lift; the
   momentum after it; a wheel click mid-inertia; the master switch off mid-flick;
   the next gesture picks up the change.
5. **Recovery** (instrumented) — the tap is stalled past the timeout three
   times; each time it is re-enabled and reverses again with no restart.
6. **Latency** (instrumented) — 5,000 callbacks timed inside the callback.
7. **Teardown** — nothing left attached.

### Defects these suites found

| Found by | Defect |
|---|---|
| TapCheck §3 | Only the line field was actually negated: `line 3 · point 30 · fixed 3.0` arrived as `line −3 · point +24 · fixed +3.0`. Writing the line field recomputes the others. |
| TapCheck §5 | After a timeout the tap stayed disabled forever: `tapDisabledByTimeout` never reached the callback. Now: watchdog. |
| TapCheck §3 | A posted scroll event's tablet subtype arrives as 0 — the Tablet rule cannot be tested synthetically. |
| Code review, pinned by §1–2 | `stop()` before the thread published its run loop was a no-op, leaving an unremovable tap. |
| Code review, pinned by §4 and Verify | The latch was released at scroll-phase ended, before the momentum it protects. |
| Code review, pinned by Verify | A tap failure was overwritten by the next 1 Hz poll, restarting the tap every second. |
| Code review, pinned by Verify | `profiles: []` in the store crashed the tap; a missing field reset all settings. |

## The built bundle

Launched with `open`, never by running the binary (a Terminal launch inherits
Terminal's Accessibility grant).

- [x] **PASSED** Launch with the existing grant: `granted` → tap installed 11 ms
      after start → "Scroll engine running" only after installation. ~1.1 s from
      `open` to running.
- [x] **PASSED** End to end through the bundle: `--running-app`, wheel reversed in
      all six fields, trackpad natural, one tap, scroll-only mask.
- [x] **PASSED** Second copy (`open -n`) while one runs: logs "already running;
      this copy is exiting", exits in about a millisecond, one process and one
      tap remain.
- [x] **PASSED** Two copies launched back to back (`open -n` twice): one
      process, one tap, reversal correct. An independent review found that the
      first guard — a `NSRunningApplication` snapshot — could let both of two
      simultaneous copies stay; it is now an exclusive `flock`.
- [x] **PASSED** Popover read through `AXUIElement`: every value comes from
      `AppState`; with only the natural trackpad attached it reads "On · Nothing
      connected is set to reverse" (it used to read "Reversing" above "Nothing is
      being reversed").
- [x] **PASSED** ⌥⌘R, synthetic key events at the HID level: stored `isEnabled`
      went true → false → true, and four presses 80 ms apart left it true.
- [x] **PASSED** ⌥⌘R while another process also registered it: both
      registrations return `noErr` and Scrollwise still toggles. A cross-process
      conflict is **not detectable** through `RegisterEventHotKey`; the UI's
      "in use elsewhere" state covers genuine registration failures only.
- [x] **PASSED** Replaced application: the same bundle re-signed ad hoc, so its
      designated requirement no longer matches the certificate-based grant, then
      launched with `open`. `AXIsProcessTrusted` reports it untrusted, the engine
      never starts, the process holds 0 taps and a wheel click arrives unchanged.
      Every surface says so: menu bar "Scrollwise, not reversing", footer
      "Accessibility needed", banner "…no scrolling is changed", master switch
      disabled, Engine "Stopped · Not attached". macOS surfaced this replacement
      as *untrusted*, not as trusted-but-refused; `grantedButTapFailed` is
      covered by the Verify transitions and by TapCheck §2.
- [x] **PASSED** Quit through the popover's Quit button: "Event tap removed" →
      "Scroll engine stopped" → "Application shut down cleanly"; 0 processes,
      0 taps.
- [x] **PASSED** No diagnostic reports for Scrollwise in
      `~/Library/Logs/DiagnosticReports`.

## Manual — input matrix — MANUAL REQUIRED

Synthetic events prove direction and latching; they do not prove feel. Requires
Accessibility granted. For each cell, confirm direction is correct and that
motion is smooth with no jitter, stutter or direction snap.

| | built-in trackpad | external trackpad | USB wheel | Bluetooth wheel | high-res wheel | Magic Mouse | tablet |
|---|---|---|---|---|---|---|---|
| slow vertical | | | | | | | |
| fast vertical | | | | | | | |
| single click/tick | n/a | n/a | | | | n/a | |
| horizontal | | | | | | | |
| momentum / flick | | | n/a | n/a | n/a | | |
| rapid direction change | | | | | | | |
| setting changed mid-flick | must **not** reverse in-flight inertia | same | n/a | n/a | n/a | same | |
| repeated scrolling, no drift | | | | | | | |

Two cells matter most because nothing automated can reach them: **Magic Mouse**
(expected to follow the Trackpad rule) and **tablet** (expected to follow the
Tablet rule only if its driver marks scroll events with a tablet subtype —
unverified).

## Manual — untouched input — MANUAL REQUIRED

Confirm none of these change while the engine is running: cursor movement, left
/ right / middle click, drag, keyboard input, pinch-zoom, rotate, swipe between
pages, Mission Control gestures, app shortcuts. The tap's mask is verified to be
`scrollWheel` only (TapCheck §1 reads it back from the window server), so the
callback is never consulted for any of them.

## Manual — lifecycle

- [x] First launch with no permission → window explains, engine stays stopped
      *(verified in an earlier session)*
- [x] Grant permission with app running → engine starts, no restart *(earlier session)*
- [ ] **MANUAL REQUIRED** Revoke permission with app running → engine stops, UI
      reports it. `tccutil reset` does not revoke a running process's trust, so
      the switch must be unticked by hand.
- [ ] **MANUAL REQUIRED** Sleep → wake → scrolling still reversed. The wake
      handler's effect (re-arm, no second tap) is PASSED in TapCheck §2; the
      real sleep cycle was not run, because sleeping the machine ends the session.
- [ ] **MANUAL REQUIRED** Start at login on → reboot → app present, engine running.
      Registration itself was verified in an earlier session.
- [ ] **MANUAL REQUIRED** Revoke login item in System Settings → the switch
      corrects itself when the popover or settings window next appears.
- [ ] **MANUAL REQUIRED** Connect/disconnect a Bluetooth mouse → list updates.
- [ ] **MANUAL REQUIRED** Clean machine, never granted anything → download the
      DMG in Safari, `shasum -a 256 -c`, drag to Applications, Gatekeeper
      blocks it, Open Anyway in Privacy & Security, grant Accessibility, scroll.
- [ ] **MANUAL REQUIRED** Update on that machine → install a newer build over it,
      Open Anyway once more, and confirm Accessibility is **still granted** with
      no re-grant. This is the test that proves self-signed distribution works
      off the build machine.

## Appearance and accessibility

- [x] Accessibility tree read via `AXUIElement` for the popover: every control
      labelled, the menu bar item's name matches the headline.
- [x] `.tertiary` prose removed from the Shortcuts pane (the rule in AGENTS.md).
- [ ] **MANUAL REQUIRED** VoiceOver heard end to end by a person.
- [ ] **MANUAL REQUIRED** Increase Contrast, Reduce Transparency, Reduce Motion —
      `com.apple.universalaccess` is TCC-protected, so not scriptable.
- [ ] **NOT RUN** Contrast re-measured on the native UI after this audit's copy
      changes. The changed strings use `.secondary`, the style measured before.

## Performance

| Metric | Method | Result |
|---|---|---|
| Callback duration | instrumented build, 5,000 live callbacks | min 0.17 µs · median 0.29 µs · p95 0.96 µs · p99 1.62 µs · max 9.12 µs |
| Idle CPU | `top -l 3 -s 3` | **0.0–0.2 %** |
| Idle memory | `ps -o rss` / `top` MEM | **47 MB RSS**, 14 MB footprint (no window open) |
| Threads | `top` | 4–5, one of which is the tap |
| Idle wake-ups | `top` IDLEW | 1 per 3 s sample — the 1 Hz permission poll and the tap watchdog coalesce |
| Startup | `open` → "Scroll engine running" in the log | ~1.1 s, of which process start → running 86 ms |

The window server's own per-tap latency figure (`CGEventTapInformation`)
reported identical min, average and maximum values in every run, so it is not
used as evidence.

The earlier ~96 MB figure was taken with the settings window open; it was not
re-measured that way. With no window, the app's own allocations are small next
to the SwiftUI and AppKit baseline.
