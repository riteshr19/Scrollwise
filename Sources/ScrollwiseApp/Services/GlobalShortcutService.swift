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

    private static let signature: OSType = 0x53_43_52_56  // 'SCRV'
    private static let identifier: UInt32 = 1

    func register(action: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
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
            Log.lifecycle.info("Registered global shortcut ⌥⌘R")
        } else {
            // Another app already owns the combination. Not fatal — everything
            // else still works — so log rather than surface an alarming error.
            Log.lifecycle.notice("⌥⌘R is already taken by another app (\(status))")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
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

    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire() }
    return noErr
}
