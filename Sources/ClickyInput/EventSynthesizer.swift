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

// MARK: - Outcomes and pacing

public enum TextEntryOutcome: Equatable, Sendable {
    case directVerified
    case pasteboardVerified
    case blocked(rule: SecureInputRule)
    case unverified(reason: String)
}

public enum PressOutcome: Equatable, Sendable {
    case axPressed
    case clickFallback(triggering: AXError)
    case noTargetPoint(triggering: AXError)
}

/// Pacing knobs; `.instant` keeps unit tests fast and deterministic.
public struct SynthesisPacing: Sendable {
    public var verificationPollCount: Int
    public var verificationPollInterval: Duration
    public var dragSteps: Int
    public var dragStepInterval: Duration
    public init(verificationPollCount: Int = 3, verificationPollInterval: Duration = .milliseconds(50),
                dragSteps: Int = 8, dragStepInterval: Duration = .milliseconds(4)) {
        self.verificationPollCount = verificationPollCount; self.verificationPollInterval = verificationPollInterval
        self.dragSteps = dragSteps; self.dragStepInterval = dragStepInterval
    }
    public static let `default` = SynthesisPacing()
    public static let instant = SynthesisPacing(verificationPollCount: 1, verificationPollInterval: .zero,
                                                dragSteps: 2, dragStepInterval: .zero)
}

// MARK: - EventSynthesizer

/// The single path from intent to synthetic input. Serialized as an actor;
/// all AX reads and event posts happen off `@MainActor`. Chunks 12–13 drive it;
/// Chunk 9's kill switch calls `releaseHeldInput()`.
public actor EventSynthesizer {
    private let poster: EventPosting
    private let elements: ElementServices
    private let secureGuard: SecureInputGuard
    private let pasteboard: PasteboardWriting
    private let pacing: SynthesisPacing
    private static let vKeyCode: CGKeyCode = 9   // ANSI 'v' — pasteboard fallback chord
    private var activeDragUpEvent: CGEventType?
    private var dragCancelled = false
    private var dragGeneration = 0

    public init(poster: EventPosting = SystemEventPoster(),
                elements: ElementServices = SystemElementServices(),
                pasteboard: PasteboardWriting = SystemPasteboard(),
                secureGuard: SecureInputGuard? = nil,
                pacing: SynthesisPacing = .default) {
        self.poster = poster; self.elements = elements; self.pasteboard = pasteboard
        self.secureGuard = secureGuard ?? SecureInputGuard(elements: elements); self.pacing = pacing
    }

    // MARK: Typing

    /// Enters `text` at keyboard focus using `keyboardSetUnicodeString` events of
    /// ≤20 UTF-16 units (grapheme-safe via `UnicodeChunker`). Verifies field value,
    /// falls back to pasteboard + ⌘V (or uses pasteboard directly when `preferPaste`),
    /// then refuses. Fail-closed: unverifiable entry refuses.
    public func typeText(_ text: String, into target: AXUIElement? = nil, preferPaste: Bool = false) async -> TextEntryOutcome {
        guard !text.isEmpty else { return .unverified(reason: "refusing to enter empty text") }
        let focused = elements.focusedElement()
        var targets: [AXUIElement] = []
        if let target { targets.append(target) }
        if let focused, !targets.contains(where: { CFEqual($0, focused) }) { targets.append(focused) }

        let entryDecision = secureGuard.decision(for: .keystrokes, targets: targets)
        guard entryDecision.allowed else { return .blocked(rule: entryDecision.ruleFired) }
        guard let focused else { return .unverified(reason: "no focused element to verify against") }

        let before = elements.stringAttribute(kAXValueAttribute as String, of: focused)
        if !preferPaste {
            for chunk in UnicodeChunker.chunk(text) {
                let recheck = secureGuard.decision(for: .keystrokes, targets: targets)
                guard recheck.allowed else { return .blocked(rule: recheck.ruleFired) }
                poster.postUnicode(chunk)
            }
            if await fieldShows(text, before: before, in: focused) { return .directVerified }
        }

        // ⌘V is itself a keystroke injection: re-check before falling back.
        let pasteDecision = secureGuard.decision(for: .keystrokes, targets: targets)
        guard pasteDecision.allowed else { return .blocked(rule: pasteDecision.ruleFired) }
        let priorClipboard = pasteboard.write(text)
        poster.postKeyChord(keyCode: Self.vKeyCode, flags: .maskCommand)
        let pasted = await fieldShows(text, before: before, in: focused)
        if let priorClipboard { pasteboard.restorePlainText(priorClipboard) }
        return pasted
            ? .pasteboardVerified
            : .unverified(reason: "field value did not reflect the text after direct entry and pasteboard fallback")
    }

    public func type(_ text: String, into target: AXUIElement? = nil) async -> TextEntryOutcome {
        await typeText(text, into: target, preferPaste: false)
    }

    private func fieldShows(_ text: String, before: String?, in element: AXUIElement) async -> Bool {
        for attempt in 0..<max(pacing.verificationPollCount, 1) {
            if attempt > 0 { try? await Task.sleep(for: pacing.verificationPollInterval) }
            if let after = elements.stringAttribute(kAXValueAttribute as String, of: element),
               after.contains(text), after != before {
                return true
            }
        }
        return false
    }

    // MARK: Pointers, scroll and keys

    /// `AXPressAction` first; on any AX failure, hover + synthetic click at
    /// `fallbackPoint` (or the element's resolved center).
    @discardableResult
    public func click(element: AXUIElement, fallbackPoint: CGPoint? = nil) -> PressOutcome {
        _ = secureGuard.decision(for: .pointerClick, targets: [element])
        let error = elements.performPress(on: element)
        if error == .success { return .axPressed }
        guard let point = fallbackPoint ?? elements.elementCenter(element) else { return .noTargetPoint(triggering: error) }
        postClick(at: point)
        return .clickFallback(triggering: error)
    }

    @discardableResult
    public func press(_ element: AXUIElement, fallbackPoint: CGPoint) -> PressOutcome {
        click(element: element, fallbackPoint: fallbackPoint)
    }

    @discardableResult
    public func click(at point: CGPoint) -> SecureInputDecision {
        let decision = secureGuard.decision(for: .pointerClick)
        postClick(at: point)
        return decision
    }

    public func moveMouse(to point: CGPoint) {
        _ = secureGuard.decision(for: .pointerMove)
        poster.postMouse(type: .mouseMoved, at: point)
    }

    @discardableResult
    public func scroll(_ direction: String, on element: AXUIElement? = nil) -> Bool {
        _ = secureGuard.decision(for: .pointerMove)
        let delta: Int32 = (direction.lowercased() == "up") ? 5 : -5
        let point = element.flatMap { elements.elementCenter($0) } ?? poster.currentCursorLocation()
        poster.postScroll(delta: delta, at: point)
        return true
    }

    @discardableResult
    public func pressKey(_ key: String, on element: AXUIElement? = nil) -> Bool {
        let decision = secureGuard.decision(for: .keystrokes, targets: element.map { [$0] } ?? [])
        guard decision.allowed else { return false }
        let keyCodes: [String: CGKeyCode] = ["return": 36, "enter": 36, "escape": 53, "esc": 53, "tab": 48, "space": 49, "down": 125, "up": 126, "left": 123, "right": 124]
        guard let keyCode = keyCodes[key.lowercased()] else { return false }
        poster.postKeyChord(keyCode: keyCode, flags: [])
        return true
    }

    /// Left-button drag with interpolated `.leftMouseDragged` events. If the
    /// kill switch fires mid-drag, `releaseHeldInput()` posts the up-event and
    /// cancels the remaining steps, so no button state is ever left held.
    public func drag(from start: CGPoint, to end: CGPoint) async {
        _ = secureGuard.decision(for: .pointerDrag)
        dragGeneration &+= 1
        let generation = dragGeneration
        dragCancelled = false; activeDragUpEvent = .leftMouseUp
        poster.postMouse(type: .leftMouseDown, at: start)
        let steps = max(pacing.dragSteps, 1)
        for step in 1...steps {
            if step > 1 {
                try? await Task.sleep(for: pacing.dragStepInterval)
                if dragCancelled || generation != dragGeneration { return }
            }
            let progress = CGFloat(step) / CGFloat(steps)
            poster.postMouse(type: .leftMouseDragged,
                             at: CGPoint(x: start.x + (end.x - start.x) * progress,
                                         y: start.y + (end.y - start.y) * progress))
        }
        guard !dragCancelled, generation == dragGeneration else { return }
        poster.postMouse(type: .leftMouseUp, at: end); activeDragUpEvent = nil
    }

    /// Kill-switch hook (Chunk 9): completes any in-flight drag with a mouse-up
    /// at the live cursor position. Key chords are posted atomically (down+up),
    /// so no modifier state is ever held. Returns true when an up-event fired.
    @discardableResult
    public func releaseHeldInput() -> Bool {
        guard let upType = activeDragUpEvent else { return false }
        dragCancelled = true; activeDragUpEvent = nil
        let location = poster.currentCursorLocation()
        poster.postMouse(type: upType, at: location)
        InputLog.synthesizer.notice("kill switch: released held drag with \(upType.rawValue, privacy: .public) at x=\(location.x, privacy: .public) y=\(location.y, privacy: .public)")
        return true
    }

    private func postClick(at point: CGPoint) {
        poster.postMouse(type: .mouseMoved, at: point)
        poster.postMouse(type: .leftMouseDown, at: point); poster.postMouse(type: .leftMouseUp, at: point)
    }
}
