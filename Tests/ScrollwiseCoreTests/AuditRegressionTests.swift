import Foundation
import Testing
@testable import ScrollwiseCore

// Regression tests for the defects found in the production audit. Each one is
// mirrored in ScrollwiseVerify, which is what runs on a machine without Xcode.

private let reverse = AxisFlip(vertical: true, horizontal: false)
private typealias RawPhase = RawScrollFields.ScrollPhase
private typealias RawMomentum = RawScrollFields.MomentumPhase

private func makeSettings(
    enabled: Bool = true,
    mouseReversed: Bool = true,
    appRules: [AppRule] = []
) -> ScrollSettings {
    let id = SettingsDefaults.defaultProfileID
    return ScrollSettings(
        isEnabled: enabled,
        profiles: [Profile(id: id, name: "Default", deviceRules: [
            DeviceRule(device: .trackpad, reverseVertical: false),
            DeviceRule(device: .mouse, reverseVertical: mouseReversed),
            DeviceRule(device: .tablet, reverseVertical: false),
        ])],
        activeProfileID: id,
        appRules: appRules,
        launchAtLogin: false,
        defaultForNewDevices: DeviceRule(device: .mouse, reverseVertical: true)
    )
}

@Suite("Raw scroll fields")
struct RawScrollFieldsTests {

    @Test("raw phases map to gesture phases")
    func phases() {
        #expect(RawScrollFields().gesturePhase == .discrete)
        #expect(RawScrollFields(scrollPhase: RawPhase.began).gesturePhase == .began)
        #expect(RawScrollFields(scrollPhase: RawPhase.mayBegin).gesturePhase == .began)
        #expect(RawScrollFields(scrollPhase: RawPhase.changed).gesturePhase == .changed)
        #expect(RawScrollFields(scrollPhase: RawPhase.ended).gesturePhase == .ended)
        #expect(RawScrollFields(scrollPhase: RawPhase.cancelled).gesturePhase == .ended)
        #expect(RawScrollFields(momentumPhase: RawMomentum.continuing).gesturePhase == .momentum)
    }

    /// The regression: scroll-phase ended released the latch before the
    /// inertia that follows it arrived.
    @Test("the lift does not end the gesture; the last momentum event does")
    func gestureEnd() {
        #expect(!RawScrollFields(scrollPhase: RawPhase.ended).endsGesture)
        #expect(RawScrollFields(momentumPhase: RawMomentum.end).endsGesture)
        #expect(RawScrollFields(scrollPhase: RawPhase.cancelled).endsGesture)
        #expect(!RawScrollFields(momentumPhase: RawMomentum.begin).endsGesture)
    }

    @Test("tablet subtypes reach the Tablet rule")
    func tabletSubtypes() {
        #expect(RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletPoint).traits.isTabletPointer)
        #expect(RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletProximity).traits.isTabletPointer)
        #expect(!RawScrollFields(mouseSubtype: 0).traits.isTabletPointer)
        let tablet = RawScrollFields(mouseSubtype: RawScrollFields.MouseSubtype.tabletPoint)
        #expect(DeviceClassifier.classify(tablet.traits) == .tablet)
    }
}

@Suite("Gesture latch across a whole flick")
struct GestureLatchFlickTests {

    @Test("a setting changed mid-flick does not reach the momentum")
    func flick() {
        var latch = GestureLatch()
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.began), proposed: reverse) == reverse)
        // The setting changes here; every later proposal is `.none`.
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.changed), proposed: .none) == reverse)
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.ended), proposed: .none) == reverse)
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.begin), proposed: .none) == reverse)
        #expect(latch.resolve(RawScrollFields(), proposed: .none) == .none)
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.continuing), proposed: .none) == reverse)
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, momentumPhase: RawMomentum.end), proposed: .none) == reverse)
        #expect(latch.resolve(RawScrollFields(isContinuous: 1, scrollPhase: RawPhase.changed), proposed: .none) == .none)
    }

    @Test("an end with no latch latches its own decision for the momentum after it")
    func endLatches() {
        var latch = GestureLatch()
        #expect(latch.resolve(phase: .ended, proposed: reverse) == reverse)
        #expect(latch.resolve(phase: .momentum, proposed: .none) == reverse)
    }
}

@Suite("Negation")
struct NegationTests {

    @Test("negation cannot trap, and stays an involution")
    func noTrap() {
        #expect(AxisDelta.negate(Int64.min) == Int64.min)
        #expect(AxisDelta.negate(Int64.max) == -Int64.max)
        #expect(AxisDelta.negate(AxisDelta.negate(-7)) == -7)
        let axis = AxisDelta(line: .min, point: 5, fixedPoint: 1)
        #expect(axis.negated.negated == axis)
    }
}

@Suite("App rule precedence under conflict")
struct AppRulePrecedenceTests {

    private let settings = makeSettings(mouseReversed: true, appRules: [
        AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma", action: .passthrough),
        AppRule(bundleIdentifier: "com.apple.Preview", displayName: "Preview", action: .forceNatural),
        AppRule(bundleIdentifier: "com.apple.Notes", displayName: "Notes", action: .forceReverse),
    ])

    @Test("master switch, then app rule, then device rule")
    func precedence() {
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop", settings: settings) == .none)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Safari", settings: settings) == reverse)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Preview", settings: settings) == .none)
        #expect(ScrollTransformer.flip(device: .trackpad, frontmostBundleID: "com.apple.Notes", settings: settings) == reverse)
        let off = makeSettings(enabled: false, appRules: settings.appRules)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Notes", settings: off) == .none)
    }
}

@Suite("Settings read back from disk")
struct LenientSettingsTests {

    private let profileID = SettingsDefaults.defaultProfileID.uuidString

    private func decode(_ json: String) -> ScrollSettings? {
        try? JSONDecoder().decode(ScrollSettings.self, from: Data(json.utf8))
    }

    @Test("missing fields cost only themselves")
    func missingFields() throws {
        let decoded = try #require(decode("""
        {"isEnabled": false, "activeProfileID": "\(profileID)",
         "profiles": [{"id": "\(profileID)", "name": "Mine", "deviceRules": [{"device": "mouse", "reverseVertical": false}]}]}
        """))
        #expect(decoded.isEnabled == false)
        #expect(decoded.rule(for: .mouse).reverseVertical == false)
        #expect(decoded.rule(for: .mouse).isEnabled == true)
        #expect(decoded.launchAtLogin == false)
        #expect(decoded.appRules.isEmpty)
    }

    @Test("bad elements are dropped and unknown actions become passthrough")
    func lossyElements() throws {
        let decoded = try #require(decode("""
        {"appRules": [{"bundleIdentifier": "com.a", "displayName": "A", "action": "somethingNewer"},
                      {"displayName": "no id"},
                      {"bundleIdentifier": "com.b", "displayName": "B", "action": "forceReverse"}]}
        """))
        #expect(decoded.appRules.map(\.bundleIdentifier) == ["com.a", "com.b"])
        #expect(decoded.appRules.first?.action == .passthrough)
    }

    @Test("normalization always leaves an active profile that exists")
    func normalization() throws {
        let empty = try #require(decode(#"{"profiles": []}"#)).normalized()
        #expect(!empty.profiles.isEmpty)
        #expect(empty.profiles.contains { $0.id == empty.activeProfileID })

        var dangling = SettingsDefaults.settings
        dangling.activeProfileID = UUID()
        #expect(dangling.normalized().activeProfileID == SettingsDefaults.defaultProfileID)

        var duplicated = SettingsDefaults.settings
        duplicated.appRules = [
            AppRule(bundleIdentifier: "com.x", displayName: "X", action: .forceReverse),
            AppRule(bundleIdentifier: "com.x", displayName: "X again"),
        ]
        let deduped = duplicated.normalized()
        #expect(deduped.appRules.count == 1)
        #expect(deduped.appRules.first?.action == .forceReverse)
    }

    @Test("activeProfile never traps, even with no profiles")
    func activeProfileNeverTraps() {
        var settings = SettingsDefaults.settings
        settings.profiles = []
        #expect(settings.activeProfile.id == SettingsDefaults.defaultProfileID)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: settings) == reverse)
    }

    @Test("a store written by 0.0.1 decodes to exactly what it held")
    func shippedFormat() {
        let shipped = decode("""
        {"launchAtLogin":false,"isEnabled":true,"defaultForNewDevices":{"reverseVertical":true,"reverseHorizontal":false,"isEnabled":true,"device":"mouse"},
         "appRules":[],"schemaVersion":1,"profiles":[{"id":"\(profileID)","deviceRules":[
          {"reverseHorizontal":false,"device":"trackpad","reverseVertical":false,"isEnabled":true},
          {"reverseHorizontal":false,"device":"mouse","reverseVertical":true,"isEnabled":true},
          {"reverseHorizontal":false,"device":"tablet","reverseVertical":false,"isEnabled":true}],"name":"Default"}],
         "activeProfileID":"\(profileID)"}
        """)
        #expect(shipped == SettingsDefaults.settings)
    }

    @Test("an unreadable store is kept, not overwritten")
    func unreadableIsBackedUp() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = Data("[1, 2, 3]".utf8)
        defaults.set(unreadable, forKey: SettingsStore.storageKey)
        #expect(SettingsStore(defaults: defaults).load() == SettingsDefaults.settings)
        #expect(defaults.data(forKey: SettingsStore.unreadableBackupKey) == unreadable)
    }
}

@Suite("Accessibility status")
struct AccessibilityStatusTests {

    @Test("trust arriving and leaving")
    func trust() {
        #expect(AccessibilityStatus.denied.polled(isTrusted: true) == .granted)
        #expect(AccessibilityStatus.granted.polled(isTrusted: false) == .denied)
    }

    /// The regression: every poll turned a failure back into `.granted`, which
    /// restarted the tap once a second and briefly claimed it was running.
    @Test("a tap failure is sticky while trust holds")
    func stickyFailure() {
        #expect(AccessibilityStatus.grantedButTapFailed.polled(isTrusted: true) == .grantedButTapFailed)
        #expect(AccessibilityStatus.grantedButTapFailed.polled(isTrusted: false) == .denied)
        #expect(AccessibilityStatus.granted.afterTapFailure(isTrusted: true) == .grantedButTapFailed)
        #expect(AccessibilityStatus.granted.afterTapFailure(isTrusted: false) == .denied)
        #expect(AccessibilityStatus.grantedButTapFailed.afterTapInstalled() == .granted)
        #expect(!AccessibilityStatus.grantedButTapFailed.allowsEngine)
    }
}

@Suite("HID: tablets with touch, and the Magic Mouse")
struct HIDAuditTests {

    private func pairs(_ raw: (Int, Int)...) -> [HIDUsage.Pair] {
        raw.map { HIDUsage.Pair(page: $0.0, usage: $0.1) }
    }

    @Test("a pen tablet with a touch surface is a tablet")
    func penOutranksTouchPad() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x0D, 0x02), (0x0D, 0x05))) == .tablet)
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x0D, 0x01), (0x0D, 0x05))) == .trackpad)
    }

    @Test("a Magic Mouse is recognised by name, or by Apple vendor and product")
    func magicMouse() {
        #expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: nil, productID: nil, name: "Magic Mouse"))
        #expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x004C, productID: 0x0269, name: "Renamed"))
        #expect(HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x05AC, productID: 0x0323, name: "Mouse"))
        #expect(!HIDPointingDeviceClassifier.isMagicMouse(vendorID: 0x046D, productID: 0x0269, name: "MX Master"))
        #expect(!HIDPointingDeviceClassifier.isMagicMouse(vendorID: nil, productID: nil,
                                                          name: "Apple Internal Keyboard / Trackpad"))
    }
}
