import Foundation
import ScrollwiseCore

// A dependency-free mirror of ScrollwiseCoreTests.
//
// The real suite in Tests/ uses swift-testing, which ships with Xcode. This
// target exists so the same assertions can be run from a Command Line Tools
// toolchain and in CI without Xcode: `swift run ScrollwiseVerify`.

var failures: [String] = []
var checks = 0

@MainActor
func expect(_ condition: Bool, _ label: String) {
    checks += 1
    if !condition { failures.append(label) }
}

@MainActor
func makeSettings(
    enabled: Bool = true,
    trackpadReversed: Bool = false,
    mouseReversed: Bool = true,
    horizontal: Bool = false,
    appRules: [AppRule] = []
) -> ScrollSettings {
    let id = SettingsDefaults.defaultProfileID
    return ScrollSettings(
        isEnabled: enabled,
        profiles: [Profile(id: id, name: "Default", deviceRules: [
            DeviceRule(device: .trackpad, reverseVertical: trackpadReversed, reverseHorizontal: horizontal),
            DeviceRule(device: .mouse, reverseVertical: mouseReversed, reverseHorizontal: horizontal),
            DeviceRule(device: .tablet, reverseVertical: false, isEnabled: false),
        ])],
        activeProfileID: id,
        appRules: appRules,
        launchAtLogin: false,
        defaultForNewDevices: DeviceRule(device: .mouse, reverseVertical: true)
    )
}

// MARK: - Transformation

let base = makeSettings()
expect(ScrollTransformer.flip(device: .trackpad, frontmostBundleID: nil, settings: base) == .none,
       "trackpad is left natural by default")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: base)
       == AxisFlip(vertical: true, horizontal: false),
       "mouse is reversed by default, vertical only")

let off = makeSettings(enabled: false, trackpadReversed: true, mouseReversed: true)
expect(PointingDeviceType.allCases.allSatisfy {
    ScrollTransformer.flip(device: $0, frontmostBundleID: nil, settings: off) == .none
}, "master switch off flips nothing")

expect(ScrollTransformer.flip(device: .tablet, frontmostBundleID: nil, settings: base) == .none,
       "a disabled device rule passes through")

expect(ScrollTransformer.flip(device: .unknown, frontmostBundleID: nil, settings: base)
       == ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: base),
       "unknown devices follow the mouse rule")

expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil,
                              settings: makeSettings(horizontal: true)).horizontal,
       "horizontal flips when opted in")
expect(!ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: base).horizontal,
       "horizontal stays off by default")

let withAppRule = makeSettings(appRules: [
    AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma", action: .passthrough)
])
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop",
                              settings: withAppRule) == .none,
       "a passthrough app rule beats the device rule")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Safari",
                              settings: withAppRule) == AxisFlip(vertical: true, horizontal: false),
       "an app rule applies only to its own app")

let disabledRule = makeSettings(appRules: [
    AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma",
            action: .passthrough, isEnabled: false)
])
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop",
                              settings: disabledRule) == AxisFlip(vertical: true, horizontal: false),
       "a disabled app rule is ignored")

let forced = makeSettings(trackpadReversed: false, appRules: [
    AppRule(bundleIdentifier: "com.apple.Preview", displayName: "Preview", action: .forceReverse)
])
expect(ScrollTransformer.flip(device: .trackpad, frontmostBundleID: "com.apple.Preview",
                              settings: forced).vertical,
       "forceReverse reverses a device that was natural")

// MARK: - Delta arithmetic

let delta = ScrollDelta(
    vertical: AxisDelta(line: 3, point: 42, fixedPoint: 4.5),
    horizontal: AxisDelta(line: -1, point: -12, fixedPoint: -1.25)
)
let flipped = delta.applying(AxisFlip(vertical: true, horizontal: false))
expect(flipped.vertical == AxisDelta(line: -3, point: -42, fixedPoint: -4.5),
       "all three vertical representations are negated together")
expect(flipped.horizontal == delta.horizontal,
       "the untouched axis is preserved exactly")
let both = AxisFlip(vertical: true, horizontal: true)
expect(delta.applying(both).applying(both) == delta, "double negation is identity")

// MARK: - Classification

expect(DeviceClassifier.classify(.init(isContinuous: true, hasPhase: true, hasMomentumPhase: false)) == .trackpad,
       "phase-bearing continuous events are a trackpad")
expect(DeviceClassifier.classify(.init(isContinuous: true, hasPhase: false, hasMomentumPhase: true)) == .trackpad,
       "momentum is still the trackpad")
expect(DeviceClassifier.classify(.init(isContinuous: false, hasPhase: false, hasMomentumPhase: false)) == .mouse,
       "discrete phase-less clicks are a wheel")
expect(DeviceClassifier.classify(.init(isContinuous: true, hasPhase: false, hasMomentumPhase: false)) == .mouse,
       "a high-resolution wheel is a mouse, not a trackpad")
expect(DeviceClassifier.classify(.init(isContinuous: true, hasPhase: true,
                                       hasMomentumPhase: false, isTabletPointer: true)) == .tablet,
       "tablet pointers win over every other signal")

// MARK: - Gesture latch

let reverse = AxisFlip(vertical: true, horizontal: false)
var latch = GestureLatch()
expect(latch.resolve(phase: .began, proposed: reverse) == reverse, "latch takes the gesture's first decision")
expect(latch.resolve(phase: .changed, proposed: .none) == reverse, "mid-gesture inherits it")
expect(latch.resolve(phase: .ended, proposed: .none) == reverse, "gesture end inherits it")
expect(latch.resolve(phase: .momentum, proposed: .none) == reverse, "momentum inherits it")

var discrete = GestureLatch()
expect(discrete.resolve(phase: .discrete, proposed: reverse) == reverse, "wheel clicks use the live decision")
expect(discrete.resolve(phase: .discrete, proposed: .none) == .none, "wheel clicks are never latched")

var resettable = GestureLatch()
_ = resettable.resolve(phase: .began, proposed: reverse)
resettable.reset()
expect(resettable.resolve(phase: .began, proposed: .none) == .none, "reset lets new settings take effect")

// MARK: - Settings

let defaults = SettingsDefaults.settings
expect(defaults.rule(for: .mouse).reverseVertical, "default: mouse reversed")
expect(!defaults.rule(for: .trackpad).reverseVertical, "default: trackpad natural")
expect(defaults.activeProfile.deviceRules.allSatisfy { !$0.reverseHorizontal },
       "default: horizontal off everywhere")

let original = SettingsDefaults.settings
let changed = original.replacingActiveRule(DeviceRule(device: .trackpad, reverseVertical: true))
expect(!original.rule(for: .trackpad).reverseVertical, "replacing a rule does not mutate the original")
expect(changed.rule(for: .trackpad).reverseVertical, "replacing a rule returns an updated copy")

let suite = "verify.\(UUID().uuidString)"
if let store = UserDefaults(suiteName: suite) {
    defer { store.removePersistentDomain(forName: suite) }
    let settingsStore = SettingsStore(defaults: store)

    expect(settingsStore.load() == SettingsDefaults.settings, "an empty store yields the shipped defaults")

    var toSave = SettingsDefaults.settings
    toSave.isEnabled = false
    toSave.appRules = [AppRule(bundleIdentifier: "com.example.App", displayName: "Example")]
    settingsStore.save(toSave)
    expect(settingsStore.load() == toSave, "settings survive a storage round trip")

    store.set(Data("not json".utf8), forKey: SettingsStore.storageKey)
    expect(settingsStore.load() == SettingsDefaults.settings,
           "unreadable data falls back to defaults rather than throwing")
} else {
    failures.append("could not open a test UserDefaults suite")
}

// MARK: - Shipped defaults must all be reachable

// No UI anywhere sets `DeviceRule.isEnabled`, so a rule shipped disabled can
// never be switched back on — its Direction control is dead for good.
for rule in SettingsDefaults.deviceRules {
    expect(rule.isEnabled, "shipped \(rule.device) rule is enabled, so its control is reachable")
}
expect(SettingsDefaults.deviceRules.contains { $0.device == .tablet },
    "a tablet rule ships, so connected tablets have something to govern them")
expect(SettingsDefaults.deviceRules.first { $0.device == .tablet }?.reverseVertical == false,
    "a tablet is still not reversed by default")

// MARK: - HID classification, transports and identity

func pair(_ page: Int, _ usage: Int) -> HIDUsage.Pair { HIDUsage.Pair(page: page, usage: usage) }

// The exact collection set an Apple Internal Keyboard / Trackpad publishes. Its
// primary usage is GenericDesktop/Mouse, which is why primary usage alone once
// made the built-in trackpad appear as a mouse — twice over.
expect(HIDPointingDeviceClassifier.classify(
    usagePairs: [pair(0x01, 0x02), pair(0x01, 0x01), pair(0x0D, 0x05), pair(0xFF00, 0x0C)],
    primaryUsagePage: 0x01, primaryUsage: 0x02) == .trackpad,
    "built-in trackpad classifies as trackpad despite primary usage Mouse")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x01, 0x02)]) == .mouse,
    "a plain mouse is a mouse")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x01, 0x02), pair(0x0D, 0x05)]) == .trackpad,
    "touch pad outranks the mouse collection beside it")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x0D, 0x02)]) == .tablet,
    "a pen digitizer is a tablet")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x0D, 0x01)]) == .tablet,
    "a bare digitizer is a tablet")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x01, 0x02), pair(0x0D, 0x02)]) == .tablet,
    "a tablet that also reports a mouse is still a tablet")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [], primaryUsagePage: 0x0D, primaryUsage: 0x05) == .trackpad,
    "primary usage is the fallback for a device with no pairs (touch pad)")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [], primaryUsagePage: 0x0D, primaryUsage: 0x02) == .tablet,
    "primary usage is the fallback for a device with no pairs (pen)")
expect(HIDPointingDeviceClassifier.classify(usagePairs: []) == .mouse,
    "a device with nothing readable falls back to mouse")

expect(HIDPointingDeviceClassifier.isInternalTransport("FIFO"), "FIFO is internal (Apple silicon)")
expect(HIDPointingDeviceClassifier.isInternalTransport("SPI"), "SPI is internal (Intel)")
expect(!HIDPointingDeviceClassifier.isInternalTransport("USB"), "USB is not internal")
expect(!HIDPointingDeviceClassifier.isInternalTransport("Bluetooth"), "Bluetooth is not internal")
expect(HIDPointingDeviceClassifier.friendlyTransport("Bluetooth Low Energy") == "Bluetooth",
    "Bluetooth Low Energy collapses to Bluetooth")
expect(HIDPointingDeviceClassifier.friendlyTransport("BluetoothLowEnergy") == "Bluetooth",
    "BluetoothLowEnergy collapses to Bluetooth")
expect(HIDPointingDeviceClassifier.friendlyTransport("USB") == "USB", "USB is named USB")
expect(HIDPointingDeviceClassifier.friendlyTransport("FIFO") == "Built-in", "FIFO is named Built-in")
expect(HIDPointingDeviceClassifier.friendlyTransport("Thunderbolt") == "Thunderbolt",
    "an unrecognised transport is passed through, not invented")

// One physical device arrives once per matched criterion; both references share
// a unique ID. This is what stops a single trackpad reading as "2 connected".
expect(HIDPointingDeviceClassifier.identity(uniqueID: 4294969678, serial: nil, vendorID: nil,
        productID: nil, locationID: 172, name: "Apple Internal Keyboard / Trackpad")
    == HIDPointingDeviceClassifier.identity(uniqueID: 4294969678, serial: nil, vendorID: nil,
        productID: nil, locationID: 172, name: "Apple Internal Keyboard / Trackpad"),
    "two references to one device collapse to a single identity")
expect(HIDPointingDeviceClassifier.identity(uniqueID: 111, serial: nil, vendorID: 0x046D,
        productID: 0xC52B, locationID: 1, name: "MX Master")
    != HIDPointingDeviceClassifier.identity(uniqueID: 222, serial: nil, vendorID: 0x046D,
        productID: 0xC52B, locationID: 2, name: "MX Master"),
    "two identical mice stay separate rows")
expect(HIDPointingDeviceClassifier.identity(uniqueID: nil, serial: "ABC123", vendorID: 1,
        productID: 2, locationID: 3, name: "Mouse") == "serial:ABC123",
    "a serial number is used when there is no unique ID")
expect(HIDPointingDeviceClassifier.identity(uniqueID: nil, serial: "", vendorID: 1,
        productID: 2, locationID: 3, name: "Mouse") == "1:2:3:Mouse",
    "an empty serial is not treated as an identity")
expect(HIDPointingDeviceClassifier.identity(uniqueID: nil, serial: nil, vendorID: nil,
        productID: nil, locationID: 1, name: "Mouse")
    != HIDPointingDeviceClassifier.identity(uniqueID: nil, serial: nil, vendorID: nil,
        productID: nil, locationID: 2, name: "Mouse"),
    "hardware with no identifiers still separates by location")

// MARK: - Login item state

// Raw 3 is .notFound, which a never-registered main app reports. Reading it as
// a refusal disabled the switch permanently, and the only way out of that state
// is the registration the disabled switch prevented.
expect(LoginItemState(rawStatus: 3) == .neverRegistered, "raw 3 is never-registered")
expect(!LoginItemState(rawStatus: 3).isEnabled, "never-registered is not enabled")
expect(!LoginItemState(rawStatus: 3).needsApproval, "never-registered needs no approval")
expect(LoginItemState(rawStatus: 2) == .requiresApproval, "raw 2 requires approval")
expect(LoginItemState(rawStatus: 2).isEnabled, "awaiting approval reads as on, so the switch does not snap back")
expect(LoginItemState(rawStatus: 2).needsApproval, "awaiting approval is surfaced")
expect(LoginItemState(rawStatus: 1) == .enabled, "raw 1 is enabled")
expect(LoginItemState(rawStatus: 1).isEnabled, "enabled is on")
expect(!LoginItemState(rawStatus: 1).needsApproval, "enabled needs no approval")
expect(LoginItemState(rawStatus: 0) == .notRegistered, "raw 0 is not registered")
expect(!LoginItemState(rawStatus: 0).isEnabled, "explicitly unregistered is off")

// MARK: - Raw scroll fields (the adapter's integers, interpreted in Core)

typealias RawPhase = RawScrollFields.ScrollPhase
typealias RawMomentum = RawScrollFields.MomentumPhase

expect(RawScrollFields().gesturePhase == .discrete, "no phase at all is a discrete wheel click")
expect(RawScrollFields(scrollPhase: RawPhase.began).gesturePhase == .began, "raw began is .began")
expect(RawScrollFields(scrollPhase: RawPhase.mayBegin).gesturePhase == .began, "raw may-begin starts a gesture")
expect(RawScrollFields(scrollPhase: RawPhase.changed).gesturePhase == .changed, "raw changed is .changed")
expect(RawScrollFields(scrollPhase: RawPhase.ended).gesturePhase == .ended, "raw ended is .ended")
expect(RawScrollFields(scrollPhase: RawPhase.cancelled).gesturePhase == .ended, "raw cancelled is .ended")
expect(RawScrollFields(momentumPhase: RawMomentum.continuing).gesturePhase == .momentum, "any momentum phase is .momentum")
// The regression: scroll-phase ended released the latch before the inertia
// that follows it arrived, so a mid-flick setting change reversed the momentum.
expect(!RawScrollFields(scrollPhase: RawPhase.ended).endsGesture, "the lift does not end the gesture — momentum follows it")
expect(RawScrollFields(momentumPhase: RawMomentum.end).endsGesture, "the last momentum event ends the gesture")
expect(RawScrollFields(scrollPhase: RawPhase.cancelled).endsGesture, "a cancelled gesture ends it")
expect(!RawScrollFields(momentumPhase: RawMomentum.begin).endsGesture, "momentum starting does not end it")
expect(RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletPoint).traits.isTabletPointer,
       "the tablet-point subtype marks a tablet pointer")
expect(RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletProximity).traits.isTabletPointer,
       "the tablet-proximity subtype marks a tablet pointer")
expect(!RawScrollFields(mouseSubtype: 0).traits.isTabletPointer, "the default subtype is not a tablet")
expect(DeviceClassifier.classify(RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletPoint).traits) == .tablet,
       "a tablet-marked scroll reaches the Tablet rule — it used to be unreachable")
expect(DeviceClassifier.classify(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.began).traits) == .trackpad,
       "raw continuous + phase is a trackpad")

// MARK: - Latch across a whole flick, as the tap drives it

var flick = GestureLatch()
expect(flick.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.began), proposed: reverse) == reverse,
       "flick: began takes the live decision")
// The user changes the setting here; every later proposal is `.none`.
expect(flick.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.changed), proposed: .none) == reverse,
       "flick: changed keeps it")
expect(flick.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.ended), proposed: .none) == reverse,
       "flick: the lift keeps it")
expect(flick.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.begin), proposed: .none) == reverse,
       "flick: momentum after the lift keeps it")
expect(flick.resolve(RawScrollFields(), proposed: .none) == .none,
       "flick: a wheel click mid-inertia takes its own live decision")
expect(flick.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.continuing), proposed: .none) == reverse,
       "flick: and leaves the trackpad's latch alone")
expect(flick.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.end), proposed: .none) == reverse,
       "flick: the final momentum event still matches")
expect(flick.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.changed), proposed: .none) == .none,
       "flick: once released, the new setting applies")

var unlatched = GestureLatch()
expect(unlatched.resolve(phase: .ended, proposed: reverse) == reverse, "an end with no latch latches its own decision")
expect(unlatched.resolve(phase: .momentum, proposed: .none) == reverse, "so the momentum after it matches")

// MARK: - Negation cannot trap

expect(AxisDelta.negate(Int64.min) == Int64.min, "negating Int64.min does not trap and has no positive counterpart")
expect(AxisDelta.negate(Int64.max) == -Int64.max, "Int64.max negates exactly")
expect(AxisDelta.negate(AxisDelta.negate(-7)) == -7, "negation stays an involution")
expect(AxisDelta(line: .min, point: 5, fixedPoint: 1).negated.negated == AxisDelta(line: .min, point: 5, fixedPoint: 1),
       "an axis holding Int64.min still round-trips")

// MARK: - App rule precedence under conflict

let conflicting = makeSettings(mouseReversed: true, appRules: [
    AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma", action: .passthrough),
    AppRule(bundleIdentifier: "com.apple.Preview", displayName: "Preview", action: .forceNatural),
    AppRule(bundleIdentifier: "com.apple.Notes", displayName: "Notes", action: .forceReverse),
])
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop", settings: conflicting) == .none,
       "Figma + reversed mouse → passthrough")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Safari", settings: conflicting) == reverse,
       "another app + reversed mouse → reversed")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Preview", settings: conflicting) == .none,
       "forceNatural beats a reversed device")
expect(ScrollTransformer.flip(device: .trackpad, frontmostBundleID: "com.apple.Notes", settings: conflicting) == reverse,
       "forceReverse with an axis-less rule reverses vertical only")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Notes",
                              settings: makeSettings(enabled: false, appRules: conflicting.appRules)) == .none,
       "the master switch beats every app rule")

// MARK: - Settings are external data: lenient decoding and normalization

func decode(_ json: String) -> ScrollSettings? {
    try? JSONDecoder().decode(ScrollSettings.self, from: Data(json.utf8))
}

let pid = SettingsDefaults.defaultProfileID.uuidString
let missingFields = decode("""
{"isEnabled": false, "activeProfileID": "\(pid)",
 "profiles": [{"id": "\(pid)", "name": "Mine", "deviceRules": [{"device": "mouse", "reverseVertical": false}]}]}
""")
expect(missingFields != nil, "a store missing fields still decodes — the synthesized decoder threw and reset everything")
expect(missingFields?.isEnabled == false, "the fields that are present are kept")
expect(missingFields?.rule(for: .mouse).reverseVertical == false, "a rule missing isEnabled keeps its direction")
expect(missingFields?.rule(for: .mouse).isEnabled == true, "and defaults to enabled")
expect(missingFields?.launchAtLogin == false && missingFields?.appRules == [], "missing fields take their defaults")

let unknownAction = decode("""
{"appRules": [{"bundleIdentifier": "com.a", "displayName": "A", "action": "somethingNewer"},
              {"displayName": "no id"},
              {"bundleIdentifier": "com.b", "displayName": "B", "action": "forceReverse"}]}
""")
expect(unknownAction?.appRules.map(\.bundleIdentifier) == ["com.a", "com.b"],
       "an app rule with no identity is dropped; the rest survive")
expect(unknownAction?.appRules.first?.action == .passthrough,
       "an action from a newer build becomes 'leave alone'")

let emptyProfiles = decode(#"{"profiles": [], "activeProfileID": "\#(UUID().uuidString)"}"#)?.normalized()
expect(emptyProfiles?.profiles.isEmpty == false, "no profiles is repaired to the default profile")
expect(emptyProfiles.map { s in s.profiles.contains { $0.id == s.activeProfileID } } == true,
       "the active profile always exists after normalization")

var handBuilt = SettingsDefaults.settings
handBuilt.profiles = []
expect(handBuilt.activeProfile.id == SettingsDefaults.defaultProfileID,
       "activeProfile does not trap with no profiles — the event tap reads it per event")
expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: handBuilt) == reverse,
       "and the transformer still decides from the default profile")

let otherProfile = Profile(name: "Other", deviceRules: [])
var dangling = SettingsDefaults.settings
dangling.profiles.append(otherProfile)
dangling.activeProfileID = UUID()
expect(dangling.normalized().activeProfileID == SettingsDefaults.defaultProfileID,
       "a dangling active profile ID falls back to the first profile")

var duplicated = SettingsDefaults.settings
duplicated.appRules = [AppRule(bundleIdentifier: "com.x", displayName: "X", action: .forceReverse),
                       AppRule(bundleIdentifier: "com.x", displayName: "X again")]
duplicated.profiles[0].deviceRules.append(DeviceRule(device: .mouse, reverseVertical: false))
let deduped = duplicated.normalized()
expect(deduped.appRules.count == 1 && deduped.appRules[0].action == .forceReverse,
       "duplicate app rules collapse to the first, so list identities stay unique")
expect(deduped.activeProfile.deviceRules.filter { $0.device == .mouse }.count == 1,
       "duplicate device rules collapse to the first")

// The exact blob the 0.0.1 build writes, captured from a real store.
let shipped = decode("""
{"launchAtLogin":false,"isEnabled":true,"defaultForNewDevices":{"reverseVertical":true,"reverseHorizontal":false,"isEnabled":true,"device":"mouse"},
 "appRules":[],"schemaVersion":1,"profiles":[{"id":"\(pid)","deviceRules":[
  {"reverseHorizontal":false,"device":"trackpad","reverseVertical":false,"isEnabled":true},
  {"reverseHorizontal":false,"device":"mouse","reverseVertical":true,"isEnabled":true},
  {"reverseHorizontal":false,"device":"tablet","reverseVertical":false,"isEnabled":true}],"name":"Default"}],
 "activeProfileID":"\(pid)"}
""")
expect(shipped == SettingsDefaults.settings, "a store written by 0.0.1 decodes to exactly what it held")

if let backupStore = UserDefaults(suiteName: "verify.backup.\(UUID().uuidString)") {
    let unreadable = Data("[1, 2, 3]".utf8)
    backupStore.set(unreadable, forKey: SettingsStore.storageKey)
    expect(SettingsStore(defaults: backupStore).load() == SettingsDefaults.settings,
           "a store of the wrong shape falls back to defaults")
    expect(backupStore.data(forKey: SettingsStore.unreadableBackupKey) == unreadable,
           "and the unreadable original is kept rather than overwritten by the next save")
} else {
    failures.append("could not open a backup test UserDefaults suite")
}

// MARK: - Accessibility status transitions

expect(AccessibilityStatus.denied.polled(isTrusted: true) == .granted, "trust arriving grants")
expect(AccessibilityStatus.granted.polled(isTrusted: false) == .denied, "trust leaving denies")
// The regression: every poll turned a tap failure back into `.granted`, which
// restarted the tap once a second and briefly claimed it was running.
expect(AccessibilityStatus.grantedButTapFailed.polled(isTrusted: true) == .grantedButTapFailed,
       "a tap failure is sticky while trust holds")
expect(AccessibilityStatus.grantedButTapFailed.polled(isTrusted: false) == .denied,
       "removing the app from the list clears it")
expect(AccessibilityStatus.granted.afterTapFailure(isTrusted: true) == .grantedButTapFailed,
       "a failed tap while trusted is reported as such")
expect(AccessibilityStatus.granted.afterTapFailure(isTrusted: false) == .denied,
       "a failed tap without trust is plain denial")
expect(AccessibilityStatus.grantedButTapFailed.afterTapInstalled() == .granted,
       "a tap that attaches clears the failure")
expect(!AccessibilityStatus.grantedButTapFailed.allowsEngine, "a tap failure never reads as working")

// MARK: - HID: tablets with touch, and the Magic Mouse

expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x0D, 0x02), pair(0x0D, 0x05)]) == .tablet,
       "a pen tablet with a touch surface is a tablet, not a trackpad")
expect(HIDPointingDeviceClassifier.classify(usagePairs: [pair(0x0D, 0x01), pair(0x0D, 0x05)]) == .trackpad,
       "a bare digitizer beside a touch pad stays a trackpad")
expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: nil, productID: nil, name: "Magic Mouse"),
       "a Magic Mouse is recognised by name")
expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x004C, productID: 0x0269, name: "Ritesh's Mouse"),
       "a renamed Magic Mouse 2 is recognised by Bluetooth vendor and product")
expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x05AC, productID: 0x0323, name: "Mouse"),
       "the USB-C Magic Mouse is recognised")
expect(!HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x046D, productID: 0x0269, name: "MX Master"),
       "a non-Apple mouse sharing a product number is not")
expect(!HIDPointingDeviceClassifier.isMagicMouse(vendorID: nil, productID: nil, name: "Apple Internal Keyboard / Trackpad"),
       "the built-in trackpad is not a Magic Mouse")

// MARK: - Report

if failures.isEmpty {
    print("PASS — \(checks) checks")
} else {
    print("FAIL — \(failures.count) of \(checks) checks failed:")
    failures.forEach { print("  ✗ \($0)") }
    exit(1)
}
