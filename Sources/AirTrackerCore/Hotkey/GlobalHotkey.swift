import Foundation
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey. Unlike CGEventTap / global
/// NSEvent monitors, this needs no Accessibility or Input Monitoring permission.
/// Default: Control+Option+C (matching sony-head-tracker's Ctrl+Alt+C).
public final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let id: UInt32

    nonisolated(unsafe) private static var nextID: UInt32 = 1

    public init(keyCode: UInt32 = UInt32(kVK_ANSI_C),
                modifiers: UInt32 = UInt32(controlKey | optionKey),
                callback: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.callback = callback
        self.id = GlobalHotkey.nextID
        GlobalHotkey.nextID += 1
    }

    public func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            let this = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            var fired = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &fired)
            if fired.id == this.id { this.callback() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x41545243), id: id) // 'ATRC'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
