import Testing
@testable import ScrollwiseCore

private func pairs(_ raw: (Int, Int)...) -> [HIDUsage.Pair] {
    raw.map { HIDUsage.Pair(page: $0.0, usage: $0.1) }
}

@Suite("HID pointing device classification")
struct HIDPointingDeviceClassifierTests {

    /// The exact collection set an Apple Internal Keyboard / Trackpad publishes.
    /// Its primary usage is GenericDesktop/Mouse, which is why primary usage
    /// alone once made the built-in trackpad appear as a mouse.
    @Test("the built-in trackpad is a trackpad despite reporting primary usage Mouse")
    func builtInTrackpad() {
        let type = HIDPointingDeviceClassifier.classify(
            usagePairs: pairs((0x01, 0x02), (0x01, 0x01), (0x0D, 0x05), (0xFF00, 0x0C)),
            primaryUsagePage: 0x01,
            primaryUsage: 0x02
        )
        #expect(type == .trackpad)
    }

    @Test("a plain mouse is a mouse")
    func plainMouse() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x01, 0x02))) == .mouse)
    }

    @Test("a touch pad collection outranks the mouse collection beside it")
    func touchPadWinsOverMouse() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x01, 0x02), (0x0D, 0x05))) == .trackpad)
    }

    @Test("a pen digitizer is a tablet")
    func penIsTablet() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x0D, 0x02))) == .tablet)
    }

    @Test("a bare digitizer is a tablet")
    func digitizerIsTablet() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x0D, 0x01))) == .tablet)
    }

    @Test("a tablet that also reports a mouse collection is still a tablet")
    func tabletWinsOverMouse() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: pairs((0x01, 0x02), (0x0D, 0x02))) == .tablet)
    }

    @Test("primary usage is the fallback when a device publishes no pairs")
    func primaryUsageFallback() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: [], primaryUsagePage: 0x0D, primaryUsage: 0x05) == .trackpad)
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: [], primaryUsagePage: 0x0D, primaryUsage: 0x02) == .tablet)
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: [], primaryUsagePage: 0x01, primaryUsage: 0x02) == .mouse)
    }

    @Test("a device with nothing readable falls back to mouse")
    func emptyFallsBackToMouse() {
        #expect(HIDPointingDeviceClassifier.classify(usagePairs: []) == .mouse)
    }
}

@Suite("HID transport naming")
struct HIDTransportTests {

    @Test("Apple's internal transports are recognised on both architectures")
    func internalTransports() {
        #expect(HIDPointingDeviceClassifier.isInternalTransport("FIFO"))   // Apple silicon
        #expect(HIDPointingDeviceClassifier.isInternalTransport("SPI"))    // Intel
        #expect(HIDPointingDeviceClassifier.isInternalTransport("spi"))
        #expect(!HIDPointingDeviceClassifier.isInternalTransport("USB"))
        #expect(!HIDPointingDeviceClassifier.isInternalTransport("Bluetooth"))
    }

    @Test("every Bluetooth spelling collapses to one label")
    func bluetoothVariants() {
        #expect(HIDPointingDeviceClassifier.friendlyTransport("Bluetooth") == "Bluetooth")
        #expect(HIDPointingDeviceClassifier.friendlyTransport("Bluetooth Low Energy") == "Bluetooth")
        #expect(HIDPointingDeviceClassifier.friendlyTransport("BluetoothLowEnergy") == "Bluetooth")
    }

    @Test("wired and internal transports get readable names")
    func otherTransports() {
        #expect(HIDPointingDeviceClassifier.friendlyTransport("USB") == "USB")
        #expect(HIDPointingDeviceClassifier.friendlyTransport("FIFO") == "Built-in")
        #expect(HIDPointingDeviceClassifier.friendlyTransport("SPI") == "Built-in")
    }

    @Test("an unrecognised transport is passed through rather than invented")
    func unknownTransportPassesThrough() {
        #expect(HIDPointingDeviceClassifier.friendlyTransport("Thunderbolt") == "Thunderbolt")
    }
}

@Suite("HID device identity")
struct HIDIdentityTests {

    /// One physical device arrives once per matched criterion. Both references
    /// carry the same unique ID, which is what collapses them into one row —
    /// the bug that reported a single trackpad as "2 connected".
    @Test("two references to one device collapse to a single identity")
    func sameDeviceCollapses() {
        let a = HIDPointingDeviceClassifier.identity(
            uniqueID: 4294969678, serial: nil, vendorID: nil, productID: nil,
            locationID: 172, name: "Apple Internal Keyboard / Trackpad")
        let b = HIDPointingDeviceClassifier.identity(
            uniqueID: 4294969678, serial: nil, vendorID: nil, productID: nil,
            locationID: 172, name: "Apple Internal Keyboard / Trackpad")
        #expect(a == b)
    }

    @Test("two identical mice stay separate rows")
    func identicalModelsStaySeparate() {
        let a = HIDPointingDeviceClassifier.identity(
            uniqueID: 111, serial: nil, vendorID: 0x046D, productID: 0xC52B, locationID: 1, name: "MX Master")
        let b = HIDPointingDeviceClassifier.identity(
            uniqueID: 222, serial: nil, vendorID: 0x046D, productID: 0xC52B, locationID: 2, name: "MX Master")
        #expect(a != b)
    }

    @Test("a serial number is used when there is no unique ID")
    func serialFallback() {
        let id = HIDPointingDeviceClassifier.identity(
            uniqueID: nil, serial: "ABC123", vendorID: 1, productID: 2, locationID: 3, name: "Mouse")
        #expect(id == "serial:ABC123")
    }

    @Test("an empty serial is not treated as an identity")
    func emptySerialIgnored() {
        let id = HIDPointingDeviceClassifier.identity(
            uniqueID: nil, serial: "", vendorID: 1, productID: 2, locationID: 3, name: "Mouse")
        #expect(id == "1:2:3:Mouse")
    }

    @Test("hardware with no identifiers at all still separates by location")
    func locationFallback() {
        let a = HIDPointingDeviceClassifier.identity(
            uniqueID: nil, serial: nil, vendorID: nil, productID: nil, locationID: 1, name: "Mouse")
        let b = HIDPointingDeviceClassifier.identity(
            uniqueID: nil, serial: nil, vendorID: nil, productID: nil, locationID: 2, name: "Mouse")
        #expect(a != b)
    }
}

@Suite("Login item state")
struct LoginItemStateTests {

    /// `.notFound` (raw 3) is what a never-registered main app reports.
    /// Reading it as a refusal disabled the switch permanently, and the only
    /// way out of that state is the registration the disabled switch prevented.
    @Test("never-registered is offerable, not refused")
    func neverRegisteredIsOfferable() {
        let state = LoginItemState(rawStatus: 3)
        #expect(state == .neverRegistered)
        #expect(!state.isEnabled)
        #expect(!state.needsApproval)
    }

    @Test("awaiting approval reads as on, so the switch does not snap back")
    func requiresApprovalCountsAsOn() {
        let state = LoginItemState(rawStatus: 2)
        #expect(state == .requiresApproval)
        #expect(state.isEnabled)
        #expect(state.needsApproval)
    }

    @Test("enabled is on and needs nothing")
    func enabled() {
        let state = LoginItemState(rawStatus: 1)
        #expect(state == .enabled)
        #expect(state.isEnabled)
        #expect(!state.needsApproval)
    }

    @Test("explicitly unregistered is off")
    func notRegistered() {
        let state = LoginItemState(rawStatus: 0)
        #expect(state == .notRegistered)
        #expect(!state.isEnabled)
    }
}
