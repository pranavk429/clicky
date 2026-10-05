import Carbon.HIToolbox

/// The local stop path shared by the scripted demo and the live runner: a Carbon
/// global hotkey on Esc. The C handler is a non-capturing closure that resolves
/// the instance from its user-data pointer.
final class EscapeHotKey {
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
                            { _, _, userData in
                                guard let userData else { return noErr }
                                let hotKey = Unmanaged<EscapeHotKey>.fromOpaque(userData).takeUnretainedValue()
                                hotKey.onFire()
                                return noErr
                            },
                            1, &eventType, selfPointer, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4B59) /* 'CLKY' */, id: 1)
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
