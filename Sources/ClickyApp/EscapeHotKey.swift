import Carbon.HIToolbox

/// The local stop path shared by the scripted demo and the live runner: a Carbon
/// global hotkey on Esc. The C handler is a non-capturing closure that resolves
/// the instance from its user-data pointer.
final class EscapeHotKey {
    /// Distinct from `GlobalHotKey`'s 'CLKY' signature: both handlers are installed on
    /// the application event target and receive every `kEventHotKeyPressed`, so each
    /// must match its own signature or it will claim the other's chords (measured
    /// 2026-10-06: Esc toggled the session and ⌘⇧Space stopped the live demo).
    private static let signature = OSType(0x434C_4B45)   // 'CLKE'

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: @Sendable () -> Void

    init(onFire: @escaping @Sendable () -> Void) {
        self.onFire = onFire
    }

    func install(_ target: EventTargetRef) {
        guard hotKeyRef == nil, handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(target,
                            { _, event, userData in
                                guard let userData else { return noErr }
                                var hotKeyID = EventHotKeyID()
                                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                                               EventParamType(typeEventHotKeyID), nil,
                                                               MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                                guard status == noErr, hotKeyID.signature == EscapeHotKey.signature else {
                                    return OSStatus(eventNotHandledErr)
                                }
                                let hotKey = Unmanaged<EscapeHotKey>.fromOpaque(userData).takeUnretainedValue()
                                hotKey.onFire()
                                return noErr
                            },
                            1, &eventType, selfPointer, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, target, 0, &hotKeyRef)
    }

    func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit { uninstall() }
}
