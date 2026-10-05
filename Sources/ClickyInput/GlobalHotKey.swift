import Carbon.HIToolbox
import Foundation

/// Carbon `RegisterEventHotKey` binding (spec §4.4; errata B13): system-wide chords with no
/// Input Monitoring permission. Zero-modifier chords are legal since 10.3 (modifier-only
/// chords lack a keycode) but a bare key shadows that key globally — Clicky ships ⌘⇧-chords.
/// Callbacks arrive on the main thread via the application event target.
public final class GlobalHotKey: @unchecked Sendable {
    public enum Action: UInt32, CaseIterable, Sendable { case sessionToggle = 1, killSwitch = 2 }

    public struct HotKey: Equatable, Sendable {
        public let action: Action
        public let keyCode: UInt32
        public let modifiers: UInt32
        public static let commandShift: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)
        /// ⌘⇧Space — session toggle (spec §4.1).
        public static let sessionToggle = HotKey(action: .sessionToggle, keyCode: UInt32(kVK_Space),
                                                 modifiers: commandShift)
        /// ⌘⇧X — hardware kill switch (spec §4.4).
        public static let killSwitch = HotKey(action: .killSwitch, keyCode: UInt32(kVK_ANSI_X),
                                              modifiers: commandShift)
    }

    private static let signature = OSType(0x434C_4B59)   // 'CLKY'
    private let hotKeys: [HotKey]
    private let onAction: @Sendable (Action) -> Void
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    public init(hotKeys: [HotKey], onAction: @escaping @Sendable (Action) -> Void) {
        self.hotKeys = hotKeys
        self.onAction = onAction
    }
    /// Whether the event handler is installed. Main thread only.
    public var isRegistered: Bool { handler != nil }

    /// Registers every chord; returns `noErr` or the first Carbon failure. Main thread only.
    @discardableResult
    public func register() -> OSStatus {
        guard handler == nil else { return noErr }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var newHandler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), Self.handleEvent, 1, &eventType,
                                         Unmanaged.passUnretained(self).toOpaque(), &newHandler)
        guard status == noErr, let newHandler else { return status }
        handler = newHandler
        for hotKey in hotKeys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: hotKey.action.rawValue)
            let registerStatus = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id,
                                                     GetApplicationEventTarget(), 0, &ref)
            guard registerStatus == noErr, let ref else {
                unregister()
                return registerStatus == noErr ? OSStatus(paramErr) : registerStatus
            }
            refs.append(ref)
        }
        return noErr
    }

    /// Unregisters every chord and removes the handler. Main thread only.
    public func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }

    private func handles(_ action: Action) -> Bool { hotKeys.contains { $0.action == action } }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr else { return OSStatus(eventNotHandledErr) }
        // Other Carbon handlers on the application target (e.g. the demo Esc hotkey)
        // receive the same kEventHotKeyPressed events; match our signature so we never
        // claim their chords (measured 2026-10-06: shared 'CLKY' + id-only matching let
        // Esc toggle the session and ⌘⇧Space stop the live demo).
        guard hotKeyID.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
        let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        guard let action = Action(rawValue: hotKeyID.id), instance.handles(action) else {
            return OSStatus(eventNotHandledErr)   // another GlobalHotKey instance may handle it
        }
        instance.onAction(action)
        return noErr
    }
}
