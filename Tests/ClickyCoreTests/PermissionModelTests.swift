// Tests/ClickyCoreTests/PermissionModelTests.swift
import XCTest
@testable import ClickyCore
final class PermissionModelTests: XCTestCase {
    func testExactDeepLinks() {
        XCTAssertEqual(PermissionKind.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(PermissionKind.screenRecording.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        XCTAssertEqual(PermissionKind.microphone.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertTrue(PermissionKind.screenRecording.guidance.contains("quit and reopen"))
    }
    func testMissingAndRevocations() {
        let s = PermissionSnapshot(accessibility: .granted, screenRecording: .denied, microphone: .notDetermined)
        XCTAssertEqual(s.missing, [.screenRecording, .microphone])
        XCTAssertFalse(s.allGranted)
        let after = PermissionSnapshot(accessibility: .denied, screenRecording: .granted, microphone: .denied)
        XCTAssertEqual(PermissionWatchdog.revocations(from: s, to: after), [.accessibility])
    }
}
