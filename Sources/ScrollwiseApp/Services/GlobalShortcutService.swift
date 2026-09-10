import AppKit
import Carbon.HIToolbox
import ScrollwiseCore

/// Registers ⌥⌘R as a system-wide hot key.
///
/// Uses `RegisterEventHotKey`, the documented Carbon API that is still the only
/// supported way to claim a global shortcut without Accessibility. It is
/// deliberately *not* built on a second `CGEventTap` for keys: watching every
/// keystroke to catch one combination would be a far larger privacy surface than
/// this app has any business taking.
@MainActor
final class GlobalShortcutService {

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Whether ⌥⌘R actually belongs to Scrollwise. The UI advertises the
    /// shortcut only while this is true; when another app owns the combination
    /// it says so instead of showing keys that do nothing.
    private(set) var isRegistered = false

    private static let signature: OSType = 0x53_43_52_56  // 'SCRV'
    private static let identifier: UInt32 = 1

    /// Attempts registration once. A refusal is not retried: the combination
    /// belongs to someone else until they release it, and polling for that
    /// would be work with no user-visible benefit.
    func register(action: @escaping () -> Void) {
        guard handlerRef == nil else { return }
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            context,
            &handlerRef
        )
        guard installed == noErr else {
            Log.lifecycle.error("Could not install hot key handler (\(installed))")
            handlerRef = nil
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            isRegistered = true
            Log.lifecycle.info("Registered global shortcut ⌥⌘R")
        } else {
            // Another app already owns the combination. Not fatal — everything
            // else still works — and the UI reports it rather than the log alone.
            hotKeyRef = nil
            isRegistered = false
            Log.lifecycle.notice("⌥⌘R is already taken by another app (\(status))")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
        isRegistered = false
    }

    fileprivate func fire() {
        action?()
    }
}

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.signature == 0x53_43_52_56 else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire() }
    return noErr
}
