import Foundation

/// The HID usage page/usage pairs this app cares about.
///
/// Declared as plain integers rather than imported from IOKit so this target
/// stays framework-free and therefore testable without hardware. The values are
/// from the USB HID Usage Tables and are fixed by that specification.
public enum HIDUsage: Sendable {
    public static let genericDesktopPage = 0x01
    public static let mouse = 0x02
    public static let pointer = 0x01

    public static let digitizerPage = 0x0D
    public static let digitizer = 0x01
    public static let pen = 0x02
    public static let touchPad = 0x05

    public struct Pair: Equatable, Sendable {
        public let page: Int
        public let usage: Int
        public init(page: Int, usage: Int) {
            self.page = page
            self.usage = usage
        }
    }
}

/// Decides what a HID device *is*, from the collections it publishes.
///
/// ## Why usage pairs and not primary usage
/// A trackpad's first top-level collection is `GenericDesktop/Mouse` — the
/// built-in MacBook trackpad reports primary usage `(1, 2)` — so primary usage
/// alone calls every trackpad a mouse. Only the presence of a
/// `Digitizer/TouchPad` collection separates them.
///
/// A related trap lives in the property keys: `kIOHIDDeviceUsagePageKey` and
/// `kIOHIDDeviceUsageKey` are *matching* keys and read back `nil` as device
/// properties. The readable equivalents are `kIOHIDPrimaryUsagePageKey` and
/// `kIOHIDPrimaryUsageKey`. Reading the matching keys and comparing two `nil`s
/// is how every device once ended up classified as a mouse.
public enum HIDPointingDeviceClassifier {

    /// Order matters: a trackpad is also a mouse, and a tablet may be too, so
    /// the more specific collection has to win.
    public static func classify(
        usagePairs: [HIDUsage.Pair],
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil
    ) -> PointingDeviceType {
        func has(_ page: Int, _ usage: Int) -> Bool {
            usagePairs.contains(HIDUsage.Pair(page: page, usage: usage))
        }

        // A pen collection exists only on pen digitizers, so it outranks the
        // touch pad a tablet with a touch surface also publishes; a trackpad
        // never has one. A bare digitizer collection is weaker evidence than a
        // touch pad, so it ranks below it.
        if has(HIDUsage.digitizerPage, HIDUsage.pen) { return .tablet }
        if has(HIDUsage.digitizerPage, HIDUsage.touchPad) { return .trackpad }
        if has(HIDUsage.digitizerPage, HIDUsage.digitizer) { return .tablet }
        if has(HIDUsage.genericDesktopPage, HIDUsage.mouse) { return .mouse }

        // Only for a device that publishes no usage pairs at all.
        if primaryUsagePage == HIDUsage.digitizerPage {
            return primaryUsage == HIDUsage.touchPad ? .trackpad : .tablet
        }
        return .mouse
    }

    /// Vendor IDs Apple hardware reports: its USB vendor ID, and its Bluetooth
    /// SIG company ID, which is what a Bluetooth Magic Mouse presents.
    public static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]

    /// Magic Mouse product IDs — original, Magic Mouse 2, and the USB‑C model —
    /// as listed in the Linux kernel's `hid-ids.h`.
    public static let magicMouseProductIDs: Set<Int> = [0x030D, 0x0269, 0x0323]

    /// Whether a device is a Magic Mouse, whose *scrolling* the Trackpad rule
    /// governs even though it is a mouse.
    ///
    /// Its top surface is a touch surface: the scroll events it produces carry
    /// gesture and momentum phases exactly as a trackpad's do, and the
    /// event-time classifier — the only thing that decides what is reversed —
    /// puts them under the Trackpad rule. Listing it under Mouse would claim a
    /// rule that never touches its scrolling.
    public static func isMagicMouse(vendorID: Int?, productID: Int?, name: String) -> Bool {
        if name.localizedCaseInsensitiveContains("magic mouse") { return true }
        guard let vendorID, let productID else { return false }
        return appleVendorIDs.contains(vendorID) && magicMouseProductIDs.contains(productID)
    }

    /// Apple's internal keyboard/trackpad reports transport "FIFO" on Apple
    /// silicon and "SPI" on Intel. Neither string appears on external hardware.
    public static func isInternalTransport(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "spi", "fifo", "built-in", "builtin": true
        default: false
        }
    }

    public static func friendlyTransport(_ raw: String) -> String {
        let lower = raw.lowercased()
        // Covers "Bluetooth", "Bluetooth Low Energy" and "BluetoothLowEnergy".
        if lower.contains("bluetooth") { return "Bluetooth" }
        switch lower {
        case "usb": return "USB"
        case "spi", "fifo", "built-in", "builtin": return "Built-in"
        default: return raw
        }
    }

    /// A stable identity for one *physical* device.
    ///
    /// `IOHIDManagerCopyDevices` returns a device once per matched criterion, so
    /// a trackpad — which matches both the mouse and the touch-pad criteria —
    /// arrives twice as two references with identical properties. They share a
    /// unique ID, so keying on it collapses them, while two identical mice, which
    /// have different unique IDs, keep separate rows. Apple's internal hardware
    /// has no serial number and no vendor or product ID, which is why neither can
    /// be the primary key.
    public static func identity(
        uniqueID: UInt64?,
        serial: String?,
        vendorID: Int?,
        productID: Int?,
        locationID: Int?,
        name: String
    ) -> String {
        if let uniqueID { return "uid:\(uniqueID)" }
        if let serial, !serial.isEmpty { return "serial:\(serial)" }
        return "\(vendorID ?? 0):\(productID ?? 0):\(locationID ?? 0):\(name)"
    }
}
