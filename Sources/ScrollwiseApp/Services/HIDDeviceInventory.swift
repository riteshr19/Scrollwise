import Foundation
import IOKit.hid
import ScrollwiseCore

/// A pointing device currently attached, for display in the UI.
struct AttachedDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: PointingDeviceType
    let transport: String?
    let isBuiltIn: Bool

    /// "Bluetooth", "USB", or "Built-in" — the subtitle in the device list.
    var subtitle: String {
        if isBuiltIn { return "Built-in" }
        return transport ?? "Connected"
    }
}

/// Enumerates attached mice, trackpads and tablets so the settings window can
/// show real hardware names instead of generic labels.
///
/// ## Scope, deliberately limited
/// This is a **display** facility only. Rules are not keyed to individual
/// devices, because macOS does not put a device identifier on the `CGEvent`
/// scroll events an event tap receives — there is no public way to tell *which*
/// attached mouse produced a given scroll. Rules therefore act on device
/// *class*, and this list exists so the user can see what that class currently
/// covers. The engine classifies live events separately, from their traits —
/// see `DeviceClassifier`.
///
/// ## Why the HID manager is never opened
/// `IOHIDManagerCopyDevices` matches and reads properties without opening the
/// devices. Opening them would start delivering input values, which requires the
/// Input Monitoring permission — a second, scarier prompt this app has no need
/// for. Enumeration alone requires no permission at all.
@MainActor
final class HIDDeviceInventory {

    private let manager: IOHIDManager
    private(set) var devices: [AttachedDevice] = []

    /// Called on the main actor after hardware is plugged in or removed.
    var onChange: (() -> Void)?

    private var isObserving = false
    private var coalescingTask: Task<Void, Never>?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, Self.matchingCriteria as CFArray)
    }

    // MARK: - Hot-plug

    /// Watches for devices arriving and leaving, so the list is right without a
    /// timer and without the user having to reopen the popover.
    ///
    /// `IOHIDManagerOpen` is deliberately **not** called. Opening is what makes
    /// macOS treat this as input monitoring and raise that permission prompt;
    /// the matching and removal callbacks fire from scheduling alone, which is
    /// all this needs. Verified: callbacks arrive with the manager unopened.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let inventory = Unmanaged<HIDDeviceInventory>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the run loop the manager is scheduled on, which is
            // the main one — the compiler just cannot prove it.
            MainActor.assumeIsolated { inventory.scheduleCoalescedRefresh() }
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        coalescingTask?.cancel()
        coalescingTask = nil
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// One physical device fires the callback once per criterion it matches, and
    /// scheduling replays a callback for everything already attached, so the
    /// burst is collapsed into a single refresh.
    private func scheduleCoalescedRefresh() {
        coalescingTask?.cancel()
        coalescingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            // Scheduling replays a callback for everything already attached, so
            // compare before announcing — otherwise the app reports a change at
            // launch when nothing changed.
            let before = self.devices
            self.refresh()
            guard self.devices != before else { return }
            self.onChange?()
        }
    }

    /// Matching is on usage *pairs*, so a device qualifies if any of its
    /// top-level collections is one of these — which is how a trackpad, whose
    /// first collection is a mouse, still matches the touch-pad criterion.
    private static var matchingCriteria: [[String: Any]] {
        [
            // Conventional mice.
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            // Trackpads present themselves as digitizer touch pads.
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
            // Graphics tablets, which the Tablet rule is about and which nothing
            // used to match — the row could only ever read "Not connected".
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_Pen],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_Digitizer],
        ]
    }

    /// Re-reads the attached hardware. Called when the settings window appears
    /// and when the popover opens — never on a timer, so an idle app does no work.
    @discardableResult
    func refresh() -> [AttachedDevice] {
        guard let matched = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            devices = []
            return devices
        }

        // A device matching more than one criterion is returned once per match,
        // so a single trackpad — which is both a mouse and a touch pad — arrives
        // twice. Collapse on identity before anything counts them, or the UI
        // reports "2 connected" for one piece of hardware and SwiftUI sees
        // duplicate ids in the same list.
        var unique: [String: AttachedDevice] = [:]
        for device in matched {
            let described = Self.describe(device)
            unique[described.id] = described
        }

        // Stable order so rows do not jump between refreshes.
        devices = unique.values.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        Log.devices.info("Found \(self.devices.count) pointing device(s): \(self.devices.map { "\($0.name) [\($0.type)]" }.joined(separator: ", "), privacy: .public)")
        return devices
    }

    private static func describe(_ device: IOHIDDevice) -> AttachedDevice {
        let name = string(device, kIOHIDProductKey)
            ?? string(device, kIOHIDManufacturerKey)
            ?? "Pointing Device"
        let rawTransport = string(device, kIOHIDTransportKey)

        return AttachedDevice(
            id: identity(device, name: name),
            name: name,
            type: classify(device),
            transport: rawTransport.map(HIDPointingDeviceClassifier.friendlyTransport),
            isBuiltIn: rawTransport.map(HIDPointingDeviceClassifier.isInternalTransport) ?? false
        )
    }

    /// The IOKit half of classification: read the collections, then hand the
    /// decision to `HIDPointingDeviceClassifier`, which is pure and tested.
    private static func classify(_ device: IOHIDDevice) -> PointingDeviceType {
        HIDPointingDeviceClassifier.classify(
            usagePairs: usagePairs(device),
            primaryUsagePage: integer(device, kIOHIDPrimaryUsagePageKey),
            primaryUsage: integer(device, kIOHIDPrimaryUsageKey)
        )
    }

    private static func usagePairs(_ device: IOHIDDevice) -> [HIDUsage.Pair] {
        guard let raw = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
                as? [[String: Int]] else { return [] }
        return raw.compactMap { pair in
            guard let page = pair[kIOHIDDeviceUsagePageKey],
                  let usage = pair[kIOHIDDeviceUsageKey] else { return nil }
            return HIDUsage.Pair(page: page, usage: usage)
        }
    }

    private static func identity(_ device: IOHIDDevice, name: String) -> String {
        HIDPointingDeviceClassifier.identity(
            uniqueID: number(device, kIOHIDUniqueIDKey)?.uint64Value,
            serial: string(device, kIOHIDSerialNumberKey),
            vendorID: integer(device, kIOHIDVendorIDKey),
            productID: integer(device, kIOHIDProductIDKey),
            locationID: integer(device, kIOHIDLocationIDKey),
            name: name
        )
    }

    private static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func integer(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func number(_ device: IOHIDDevice, _ key: String) -> NSNumber? {
        IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber
    }
}
