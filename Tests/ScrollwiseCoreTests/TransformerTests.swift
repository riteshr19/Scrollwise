import Testing
@testable import ScrollwiseCore

// The whole point of keeping the decision layer free of CoreGraphics: every rule
// below is verified without synthesising a single physical scroll event.

private func settings(
    enabled: Bool = true,
    trackpadReversed: Bool = false,
    mouseReversed: Bool = true,
    horizontal: Bool = false,
    appRules: [AppRule] = []
) -> ScrollSettings {
    let id = SettingsDefaults.defaultProfileID
    let rules = [
        DeviceRule(device: .trackpad, reverseVertical: trackpadReversed, reverseHorizontal: horizontal),
        DeviceRule(device: .mouse, reverseVertical: mouseReversed, reverseHorizontal: horizontal),
        DeviceRule(device: .tablet, reverseVertical: false, isEnabled: false),
    ]
    return ScrollSettings(
        isEnabled: enabled,
        profiles: [Profile(id: id, name: "Default", deviceRules: rules)],
        activeProfileID: id,
        appRules: appRules,
        launchAtLogin: false,
        defaultForNewDevices: DeviceRule(device: .mouse, reverseVertical: true)
    )
}

@Suite("Scroll transformation")
struct ScrollTransformerTests {

    @Test("trackpad and mouse are decided independently")
    func devicesAreIndependent() {
        let s = settings(trackpadReversed: false, mouseReversed: true)
        #expect(ScrollTransformer.flip(device: .trackpad, frontmostBundleID: nil, settings: s) == .none)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: s)
                == AxisFlip(vertical: true, horizontal: false))
    }

    @Test("master switch off means nothing is ever flipped")
    func masterSwitchWins() {
        let s = settings(enabled: false, trackpadReversed: true, mouseReversed: true)
        for device in PointingDeviceType.allCases {
            #expect(ScrollTransformer.flip(device: device, frontmostBundleID: nil, settings: s) == .none)
        }
    }

    @Test("a disabled device rule is passed through untouched")
    func disabledRuleIsPassthrough() {
        let s = settings()
        #expect(ScrollTransformer.flip(device: .tablet, frontmostBundleID: nil, settings: s) == .none)
    }

    @Test("an unknown device is governed by the mouse rule")
    func unknownFallsBackToMouse() {
        let s = settings(mouseReversed: true)
        #expect(ScrollTransformer.flip(device: .unknown, frontmostBundleID: nil, settings: s)
                == ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: s))
    }

    @Test("horizontal is only flipped when explicitly asked for")
    func horizontalIsOptIn() {
        let off = settings(horizontal: false)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: off).horizontal == false)

        let on = settings(horizontal: true)
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: nil, settings: on).horizontal == true)
    }

    @Test("a passthrough app rule beats the device rule")
    func appRuleOverridesDevice() {
        let s = settings(mouseReversed: true, appRules: [
            AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma", action: .passthrough)
        ])
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop", settings: s) == .none)
        // ...but only for that app.
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.apple.Safari", settings: s)
                == AxisFlip(vertical: true, horizontal: false))
    }

    @Test("a disabled app rule is ignored")
    func disabledAppRuleIsIgnored() {
        let s = settings(mouseReversed: true, appRules: [
            AppRule(bundleIdentifier: "com.figma.Desktop", displayName: "Figma",
                    action: .passthrough, isEnabled: false)
        ])
        #expect(ScrollTransformer.flip(device: .mouse, frontmostBundleID: "com.figma.Desktop", settings: s)
                == AxisFlip(vertical: true, horizontal: false))
    }

    @Test("forceReverse turns reversal on for a device that had it off")
    func forceReverseWorksOnNaturalDevice() {
        let s = settings(trackpadReversed: false, appRules: [
            AppRule(bundleIdentifier: "com.apple.Preview", displayName: "Preview", action: .forceReverse)
        ])
        let flip = ScrollTransformer.flip(device: .trackpad, frontmostBundleID: "com.apple.Preview", settings: s)
        #expect(flip.vertical == true)
    }

    @Test("all three representations of an axis are negated together")
    func everyRepresentationIsNegated() {
        let delta = ScrollDelta(
            vertical: AxisDelta(line: 3, point: 42, fixedPoint: 4.5),
            horizontal: AxisDelta(line: -1, point: -12, fixedPoint: -1.25)
        )
        let result = delta.applying(AxisFlip(vertical: true, horizontal: false))

        #expect(result.vertical == AxisDelta(line: -3, point: -42, fixedPoint: -4.5))
        // The untouched axis must survive byte-identical.
        #expect(result.horizontal == delta.horizontal)
    }

    @Test("flipping twice returns the original value")
    func negationIsAnInvolution() {
        let delta = ScrollDelta(vertical: AxisDelta(line: 7, point: 99, fixedPoint: 12.75))
        let flip = AxisFlip(vertical: true, horizontal: true)
        #expect(delta.applying(flip).applying(flip) == delta)
    }
}
