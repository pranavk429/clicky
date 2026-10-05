import ApplicationServices
import CoreGraphics
import Foundation
@testable import ClickyInput

/// Canned AX answers. `valueReads` are returned in order for `kAXValueAttribute`
/// reads (the last repeats); guard attributes come from `attributes`.
final class FakeElementServices: ElementServices, @unchecked Sendable {
    var attributes: [String: String] = [:]
    var valueReads: [String?] = [nil]
    var focused: AXUIElement?
    var pressResult: AXError = .success
    private(set) var pressedElements: [AXUIElement] = []
    private var readIndex = 0

    func performPress(on element: AXUIElement) -> AXError {
        pressedElements.append(element)
        return pressResult
    }
    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        if attribute == (kAXValueAttribute as String) {
            defer { readIndex += 1 }
            return readIndex < valueReads.count ? valueReads[readIndex] : valueReads.last ?? nil
        }
        return attributes[attribute]
    }
    func focusedElement() -> AXUIElement? { focused }
    var elementCenterPoint: CGPoint? = CGPoint(x: 120, y: 240)
    func elementCenter(_ element: AXUIElement) -> CGPoint? { elementCenterPoint }
}

/// A stable opaque AX handle for fakes — never sent to a real process.
func makeSentinelElement() -> AXUIElement {
    AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
}

/// Records posted events instead of posting them (no permissions needed).
final class RecordingEventPoster: EventPosting, @unchecked Sendable {
    var unicodeChunks: [String] = []
    var chords: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
    var mouseEvents: [(type: CGEventType, point: CGPoint)] = []
    var scrollEvents: [(delta: Int32, point: CGPoint)] = []
    var cursorLocation = CGPoint(x: 10, y: 20)
    func postUnicode(_ text: String) { unicodeChunks.append(text) }
    func postKeyChord(keyCode: CGKeyCode, flags: CGEventFlags) { chords.append((keyCode, flags)) }
    func postMouse(type: CGEventType, at point: CGPoint) { mouseEvents.append((type, point)) }
    func postScroll(delta: Int32, at point: CGPoint) { scrollEvents.append((delta, point)) }
    func currentCursorLocation() -> CGPoint { cursorLocation }
}

/// Records the pasteboard fallback and restores.
final class RecordingPasteboard: PasteboardWriting, @unchecked Sendable {
    var previousString: String? = "old clipboard"
    private(set) var written: [String] = []
    private(set) var restored: [String] = []
    func write(_ text: String) -> String? { written.append(text); return previousString }
    func restorePlainText(_ text: String) { restored.append(text) }
}

func makeTestSynthesizer(poster: RecordingEventPoster,
                         elements: FakeElementServices,
                         pasteboard: RecordingPasteboard = RecordingPasteboard(),
                         secureInputEnabled: @escaping @Sendable () -> Bool = { false },
                         pacing: SynthesisPacing = .instant) -> EventSynthesizer {
    EventSynthesizer(poster: poster,
                     elements: elements,
                     pasteboard: pasteboard,
                     secureGuard: SecureInputGuard(elements: elements, isSecureInputEnabled: secureInputEnabled),
                     pacing: pacing)
}
