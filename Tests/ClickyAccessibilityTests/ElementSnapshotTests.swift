import ApplicationServices
import XCTest
@testable import ClickyAccessibility

final class ElementSnapshotTests: XCTestCase {
    func testCacheKeyNormalizationAndSnapshotProjection() {
        let key = CacheKey(role: "AXButton", subrole: "", title: "  Save ", description: "Saves the Document")
        XCTAssertEqual(key.role, "axbutton")
        XCTAssertEqual(key.subrole, "")
        XCTAssertEqual(key.title, "save")
        XCTAssertEqual(key, CacheKey(role: "axbutton", subrole: "", title: "SAVE", description: "saves the document"))
        let snapshot = ElementSnapshot(element: AXUIElementCreateSystemWide(), key: key,
                                       frame: CGRect(x: 100, y: 60, width: 40, height: 20),
                                       isEnabled: true, isSecureField: false, actions: ["AXPress"],
                                       value: "clicky repo")
        XCTAssertEqual(snapshot.normalizedPoint, CGPoint(x: 120, y: 70))
        XCTAssertEqual(snapshot.actions, ["AXPress"])
        XCTAssertEqual(snapshot.value, "clicky repo")
        // Value is deliberately NOT part of CacheKey identity — it changes far
        // more often than role/subrole/title/description.
        XCTAssertEqual(key, CacheKey(role: "AXButton", subrole: "", title: "Save", description: "Saves the Document"))
    }
    func testStoredValueBoundsLengthAndRedactsSecureFields() {
        XCTAssertEqual(ElementSnapshot.maxStoredValueLength, 500)
        XCTAssertEqual(ElementSnapshot.storedValue("clicky repo", isSecure: false), "clicky repo")
        XCTAssertEqual(ElementSnapshot.storedValue("hunter2", isSecure: true), "")
        let long = String(repeating: "x", count: 700)
        XCTAssertEqual(ElementSnapshot.storedValue(long, isSecure: false), String(long.prefix(500)))
    }
    func testSecureFieldDetection() {
        // Errata B1: AXSecureTextField is a SUBROLE — the role is usually AXTextField.
        // Then the Electron/web fallback heuristics: whole-word keywords + protected content.
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXTextField", subrole: "AXSecureTextField", title: nil, placeholder: nil))
        XCTAssertFalse(ElementSnapshot.looksSecure(role: "AXTextField", subrole: nil, title: "Search", placeholder: nil))
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXTextField", subrole: nil, title: "Enter password", placeholder: nil))
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXTextField", subrole: nil, title: nil, placeholder: "OTP"))
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXTextField", subrole: nil, title: "Enter PIN", placeholder: nil))
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXProtectedContent", subrole: nil, title: nil, placeholder: nil))
        XCTAssertTrue(ElementSnapshot.looksSecure(role: "AXTextField", subrole: nil, title: "पासवर्ड टाका", placeholder: nil))
        XCTAssertFalse(ElementSnapshot.looksSecure(role: "AXButton", subrole: nil, title: "Spinner", placeholder: nil))
    }
}
