import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

// MARK: - Seams (OS touchpoints isolated behind protocols for faking)

/// Where synthesized events are posted. One `postUnicode` call carries one
/// `keyboardSetUnicodeString` event of ≤20 UTF-16 units; only
/// `EventSynthesizer` calls it, always with `UnicodeChunker` output.
public protocol EventPosting: Sendable {
    func postUnicode(_ text: String)
    func postKeyChord(keyCode: CGKeyCode, flags: CGEventFlags)
    func postMouse(type: CGEventType, at point: CGPoint)
    func postScroll(delta: Int32, at point: CGPoint)
    func currentCursorLocation() -> CGPoint
}

/// The minimal AX surface input synthesis needs: pressing an element and
/// reading string attributes (value for verification; role/subrole/title for
/// the secure-input guard). Faked in tests.
public protocol ElementServices: Sendable {
    func performPress(on element: AXUIElement) -> AXError
    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String?
    func focusedElement() -> AXUIElement?
    func elementCenter(_ element: AXUIElement) -> CGPoint?
}

/// Pasteboard seam for the verify-then-pasteboard fallback.
public protocol PasteboardWriting: Sendable {
    /// Replaces the general pasteboard string. Returns the previous plain
    /// string (nil when the pasteboard held no string) for best-effort restore.
    func write(_ text: String) -> String?
    func restorePlainText(_ text: String)
}

public enum InputLog {
    public static let synthesizer = Logger(subsystem: "com.clicky.mac", category: "input.synthesizer")
    public static let secureInput = Logger(subsystem: "com.clicky.mac", category: "input.secure")
}

// MARK: - System implementations (the only path to real hardware events)

public struct SystemEventPoster: EventPosting {
    public init() {}
    public func postUnicode(_ text: String) {
        let units = Array(text.utf16)
        guard !units.isEmpty,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    public func postKeyChord(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    public func postMouse(type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }
    public func postScroll(delta: Int32, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
        event.location = point; event.post(tap: .cghidEventTap)
    }
    public func currentCursorLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

public struct SystemElementServices: ElementServices {
    public init() {}
    public func performPress(on element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
    public func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }
    public func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)   // type id checked above
    }
    public func elementCenter(_ element: AXUIElement) -> CGPoint? {
        var posVal: CFTypeRef?, sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posVal, let sizeVal else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos); AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    }
}

public struct SystemPasteboard: PasteboardWriting {
    public init() {}
    public func write(_ text: String) -> String? {
        let board = NSPasteboard.general, prev = board.string(forType: .string)
        board.clearContents(); board.setString(text, forType: .string)
        return prev
    }
    public func restorePlainText(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents(); board.setString(text, forType: .string)
    }
}
