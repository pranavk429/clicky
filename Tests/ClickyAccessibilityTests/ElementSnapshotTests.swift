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
                                       isEnabled: true, isSecureField: false, actions: ["AXPress"])
        XCTAssertEqual(snapshot.normalizedPoint, CGPoint(x: 120, y: 70))
        XCTAssertEqual(snapshot.actions, ["AXPress"])
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
