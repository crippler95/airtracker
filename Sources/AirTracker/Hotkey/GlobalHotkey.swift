import Foundation
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey. Unlike CGEventTap / global
/// NSEvent monitors, this needs no Accessibility or Input Monitoring permission.
/// Default: Control+Option+C (matching sony-head-tracker's Ctrl+Alt+C).
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let this = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            this.callback()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x41545243), id: 1) // 'ATRC'
        RegisterEventHotKey(UInt32(kVK_ANSI_C),
                            UInt32(controlKey | optionKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
