import AppKit
import Carbon
import CoreGraphics
import XCTest
import ClickyInput

/// Live checks against the real WindowServer and AX tree. Skipped unless
/// CLICKY_INPUT_INTEGRATION=1; the terminal that runs them needs Accessibility
/// permission (System Settings → Privacy & Security → Accessibility).
final class InputIntegrationTests: XCTestCase {
    func testTypeDevanagariIntoFocusedField() async throws {
        try requireIntegrationEnvironment()
        try await waitForFrontmost("com.apple.TextEdit")
        let text = "नमस्ते, सफारी उघड आणि पुण्याचे हवामान शोध."
        let outcome = await EventSynthesizer().typeText(text)
        XCTAssertEqual(outcome, .directVerified, "Expected direct keyboardSetUnicodeString entry to verify in TextEdit")
    }

    func testSecureInputBlocksKeystrokesButNotClicks() throws {
        try requireIntegrationEnvironment()
        try XCTSkipUnless(IsSecureEventInputEnabled(), "Enable Terminal → Secure Keyboard Entry first")
        let guardInstance = SecureInputGuard(elements: SystemElementServices())
        let keystrokes = guardInstance.evaluate()
        XCTAssertFalse(keystrokes.isAllowed)
        XCTAssertEqual(keystrokes.rule, .globalSecureEventInput)
        let click = guardInstance.evaluate(operation: .pointerClick)
        XCTAssertTrue(click.isAllowed)
        XCTAssertEqual(click.rule, .globalSecureEventInput)
    }

    func testPointerMoveReachesWindowServer() async throws {
        try requireIntegrationEnvironment()
        let target = CGPoint(x: 240, y: 240)
        await EventSynthesizer().moveMouse(to: target)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(CGEvent(source: nil)?.location, target)
    }

    private func requireIntegrationEnvironment() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLICKY_INPUT_INTEGRATION"] == "1",
                          "Set CLICKY_INPUT_INTEGRATION=1; requires Accessibility permission for this terminal")
    }

    private func waitForFrontmost(_ bundleID: String) async throws {
        let deadline = Date().addingTimeInterval(20)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID, Date() < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, bundleID,
                       "Focus a TextEdit document within 20 s — the click target must be the frontmost app")
    }
}
