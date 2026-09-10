# Frontend audit — `Scrollwise 2026.dc.html`

Audited before any code was written. Rendered at 1470×812 in Chrome over a local
HTTP server, light and dark, all four options.

## 1. What the file actually is

The brief describes it as "the complete frontend." It is not. It is a Claude
Design **canvas** containing four *mutually exclusive* architecture proposals,
each shown light and dark:

| Option | Shape | Panes actually drawn |
|---|---|---|
| 1a | Toolbar tabs, tinted glass | Scrolling only |
| 1b | Sidebar + detail, clear glass | Devices only (sidebar lists 7) |
| 1c | One scrolling page, floating glass toolbar | Scrolling + General |
| 1d | Menu bar popover, specular glass | The whole app, condensed |

Nothing in it is interactive. There is no onboarding, no Accessibility
permission flow, no error state, no empty state, no disabled state, no loading
state, and no Apps or Profiles pane anywhere — the sidebar names them but no
option draws them. The canvas's own closing line asks for exactly these
("build out 1b's Apps and Profiles panes", "add the first-run Accessibility
permission flow"), which confirms the reading.

**Consequence:** the canvas is a valid *product* specification and an invalid
*implementation* specification. It was treated as the former.

**Direction chosen:** 1b as the settings window, 1d as the menu bar popover.
They are complementary rather than alternatives — 1d is the surface used daily,
1b is where depth lives.

## 2. Defect found and fixed in the canvas

18 inline `style` attributes contained unescaped double quotes:

```html
<div style="font:600 12px/1 -apple-system,"SF Pro Text","Helvetica Neue",…">
```

The attribute terminates at the first `"` before `SF`, so everything after it
became stray attributes. Every section caption — "Axes", "Shortcut", "General",
"New devices", "Devices" — lost its size, colour and padding and rendered as
full-strength 16px body text, visually outweighing the content it labelled.
Present in all four options, light and dark.

Fixed by switching the inner quotes to single quotes, on the 18 inline
attributes only; the identical stack inside the `<style>` block is valid there
and was left alone. Re-rendered and confirmed. Original saved alongside.

## 3. Glass fidelity — the headline finding

**The canvas implements glassmorphism. macOS 26 does not use glassmorphism; it
uses Liquid Glass. They are different things, and the difference is not
stylistic — it is architectural.**

`backdrop-filter` blurs *page content behind the element*. macOS materials
sample *the actual desktop behind the window*. In the canvas this is papered
over by drawing a fake wallpaper `<div>` behind each mockup — which is exactly
why the effect cannot survive being ported as-is. Specifically:

| Canvas | Real macOS 26 | Effect of shipping the canvas value |
|---|---|---|
| `backdrop-filter: blur(48–60px) saturate(180–200%)` | System materials blur far tighter and desaturate slightly | Reads as frosted plastic, not glass |
| `inset 0 1px 0 rgba(255,255,255,.85)` — a uniform top-edge sheen | Liquid Glass **refracts at the rim**, so highlight intensity varies around the perimeter | The single defining Liquid Glass trait is absent; 1d's "full specular glass" is one linear gradient |
| `#0071e3` | `controlAccentColor` | Apple's *marketing* blue from apple.com, not the system accent. Ignores the user's Appearance choice; stays blue under Graphite |
| Fixed `rgba(0,0,0,.42–.48)` captions at 10.5–12px | Semantic `.secondary` over vibrancy | ≈3.5:1 or below on the tinted grounds — fails WCAG AA for small text in both themes |
| No Reduce Transparency handling | Materials fall back automatically | Unreadable for users who enable it |

**This is why the app is native rather than a WKWebView.** In a web view none of
the above is fixable: there is no API by which page CSS can sample the desktop.
Retaining the HTML would have meant shipping a permanent, unfixable imitation of
the platform it runs on, plus the entire JS↔native bridge attack surface
described in §§36–37 of the brief. Both disappear by building natively.

In the implementation, glass comes from the system and is never hand-rolled:

- `MenuBarExtra(style: .window)` — the popover's own Liquid Glass material (1d)
- `NavigationSplitView` — the system sidebar material (1b)
- `.glassEffect(...)` — **not used at all**; see below
- `.background(.background.secondary)`, `.bar`, `.separator` — semantic, so
  Reduce Transparency and Increase Contrast work with no extra code

### Canvas contrast, remediated

The canvas's own text colours were audited in a browser by compositing each
element's colour over every background it could sit on — including each stop of
every gradient ancestor, so glass surfaces are bounded by their worst case rather
than guessed at. 206 declarations were rewritten in all — 163 text colours, 12
accent fills, one chip, 26 tile gradients and 4 disclosure marks:

| token | was | now |
|---|---|---|
| black secondary text | .28 – .50 | **.56** |
| white secondary text | .30 – .50 | **.59** |
| white tertiary / control text | .55, .58 | **.61, .68** |
| accent text (light) | `#0071e3` (3.88:1) | **`#0058b0`** |
| accent text (dark) | `#0a84ff` (4.47:1) | **`#4aa3ff`** |

The 25 `background:` uses of the accent are untouched, so the design keeps its
accent colour; only text drawn *in* that colour was darkened.

The two remaining failures were white on a fill, so alpha could not reach them —
the fills themselves were darkened, by the smallest amount that clears the bar:

| fill | was | now | white text |
|---|---|---|---|
| dark-mode accent | `#0a84ff` | **`#0974e0`** (88 % brightness, hue kept) | 3.65 -> **4.57:1** |
| "Design" chip | `rgba(255,255,255,.22)` | **`.16`** | 4.00 -> **4.60:1** |

The light-mode accent `#0071e3` already cleared it at 4.70:1 and is unchanged.

**Result: 0 failures across 191 text elements. The lowest contrast anywhere in the
canvas is 4.51:1.** This is a deliberate departure from macOS, which uses a
lighter systemBlue in dark mode and does not itself reach 4.5:1 with white — the
canvas now prioritises the standard over matching the platform exactly.

### Icon tiles darkened for full compliance

The white glyphs on the tinted app-icon tiles were initially left alone as
decorative marks with adjacent text labels — the reasoning behind `SymbolTile`'s
`accessibilityHidden(true)` in the app, and the standard Apple does not itself
meet. That exemption was declined: full AA compliance was chosen over icon
fidelity, so all ten tile gradients were darkened by the smallest factor that
brings white to 4.5:1 on the *lightest* stop of each.

| tile | was | now | brightness | white text |
|---|---|---|---|---|
| blue | `#5cb0ff -> #0a5bd6` | `#3f79b0 -> #073f94` | 69 % | 2.31 -> 4.5:1 |
| green (Shortcuts) | `#5fd08a -> #1f9a56` | `#3c8357 -> #146136` | 63 % | 1.93 -> 4.5:1 |
| mint | `#9ad9a0 -> #3a9e58` | `#597e5d -> #225c33` | 57 % | 1.64 -> 4.5:1 |
| pink | `#ff8ea8 -> #d63a63` | `#ab5f71 -> #8f2742` | 67 % | 2.17 -> 4.5:1 |
| orange | `#ff9f5a -> #e8642a` | `#a6673a -> #97411b` | 65 % | 2.03 -> 4.5:1 |
| indigo | `#8fa4ff -> #3b4fd6` | `#6473b2 -> #293796` | 70 % | 2.35 -> 4.5:1 |
| purple | `#a97bff -> #6b3fd4` | `#8661c9 -> #5532a7` | 79 % | 3.02 -> 4.5:1 |
| grey ×3 | `#b7b7bd -> #7e7e85` etc. | `#757579 -> #515155` etc. | 64–83 % | 2.00 -> 4.5:1 |

Both stops of each gradient are scaled by the same factor, so each tile keeps its
hue and its internal light-to-dark falloff; the palette is simply more muted than
macOS's. The `▾` disclosure marks went from `rgba(255,255,255,.59)` to `.67`.

**Final state: 240 of 240 text nodes at or above 4.5:1, with no exclusions of any
kind. The lowest contrast anywhere in the canvas is 4.51:1.**

The trade-off is explicit and deliberate: the tiles no longer show the colours the
real apps use, and the accent is darker than macOS's. The canvas prioritises the
standard over depicting the platform exactly.

One measurement note worth keeping: an attempt to verify this from a downscaled
JPEG screenshot reported ~2.9:1 for text that computes to 4.5:1. A control
measurement on known 14:1 text read 9–12:1 on the same image, which showed the
instrument — not the page — was at fault. Downscaling and JPEG both blend glyph
edges and understate small text.

### Correction: two claims in an earlier draft of this document were wrong

**`.glassEffect` was used once, and it rendered nothing.** It sat on the
popover's header tile, but `SymbolTile` fills that exact shape with an opaque
gradient, and glass draws *behind* its content — so the material was completely
covered. Measured against the same tile with the modifier deleted, over
different regions of a vivid gradient: mean RGB identical to one decimal place,
maximum interior difference 2.5/255. Removing the fill instead produced a 172/255
difference, i.e. real glass. The call has been removed; nesting glass inside the
popover's own glass would have been wrong even had it rendered.

**The settings window's sidebar is opaque, and that is correct.** An earlier
reading of this document treated the flat sidebar as a defect and concluded the
window needed `isOpaque = false` plus a behind-window `NSVisualEffectView`. That
was checked against Apple's own System Settings on the same machine, over the
same backdrop:

| surface | mean luminance | std. dev. |
|---|---|---|
| System Settings sidebar (macOS 26.5, dark) | 44.8 | **0.57** |
| Scrollwise sidebar, as shipped | 42.4 | 0.89 |
| Scrollwise with the "fix" applied | 60.2 | 0.69 |

Apple's own sidebar shows no backdrop bleed at all. The shipped sidebar was
already within ~2 luminance units of it; the proposed change moved it 15 units
too light, i.e. further from native. It was reverted in full. The lesson worth
keeping: measure the platform before concluding the platform is being missed.

## 4. Control inventory → native mapping

| Canvas control | Native surface | Backed by |
|---|---|---|
| "Reverse scrolling" master toggle | `ScrollingPane`, `MenuBarView` header | `AppState.setEnabled` → `ScrollSettings.isEnabled` |
| Vertical / Horizontal axis toggles | `ScrollingPane.axesSection` | `DeviceRule.reverseVertical` / `.reverseHorizontal` |
| Per-device Natural/Reversed picker | `DevicesPane`, `MenuBarView.deviceRow` | `DeviceRule` per `PointingDeviceType` |
| Device rows w/ real hardware names | `DevicesPane` device list | `HIDDeviceInventory` (IOKit, display only) |
| "Default for anything new" | `DevicesPane.newDeviceSection` | `ScrollSettings.defaultForNewDevices` |
| Profile popup / segmented control | `ProfileToolbarItem`, `MenuBarView.profilePicker` | `Profile`, `activeProfileID` |
| "Skip in this app — Figma" | `MenuBarView.appAndLoginSection` | `AppRule(.passthrough)` + `FrontmostAppMonitor` |
| "All app rules ›" | `AppsPane` | `ScrollSettings.appRules` |
| ⌥⌘R shortcut chips | `ShortcutsPane`, popover footer | `GlobalShortcutService` (`RegisterEventHotKey`) |
| "Start at login" | `GeneralPane`, popover | `LaunchAtLoginService` (`SMAppService`) |
| "Version 0.0.1 · Accessibility granted" | Sidebar footer | `AccessibilityService` for the permission half; the number is read from the bundle, never hard-coded |
| Settings… / Quit | Popover footer | `SettingsWindowPresenter`, `NSApp.terminate` |

## 5. States the canvas did not draw, now implemented

Accessibility denied · Accessibility granted-but-tap-refused · engine
reconnecting · device class not connected · no app rules (empty state) · login
item unavailable · master switch off (dependent controls disabled, not merely
dimmed) · first-run window presentation.

## 6. Scope reduction, and why

The canvas shows **per-physical-device** switches — "Built-in Trackpad",
"MX Master 4S" and "Magic Mouse" each with their own control.

This is not implementable with public API. Scroll events arriving at a
`CGEventTap` carry no device identifier; there is no supported way to learn
which of two attached mice produced a given scroll. Rendering three independent
switches that secretly all move together would be precisely the fake
functionality §59 of the brief forbids.

Implemented instead: the rule belongs to the device *class*, and the real
hardware it currently covers is listed beneath it, read from IOKit. Same
information, honestly arranged. The Devices pane says so in plain language.
