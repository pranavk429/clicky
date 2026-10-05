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
