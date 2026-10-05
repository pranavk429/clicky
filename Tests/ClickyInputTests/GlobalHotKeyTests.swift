// Tests/ClickyInputTests/GlobalHotKeyTests.swift
import Carbon.HIToolbox
import XCTest
@testable import ClickyInput

final class GlobalHotKeyTests: XCTestCase {
    func testChordConstants() {
        XCTAssertEqual(GlobalHotKey.HotKey.killSwitch.keyCode, UInt32(kVK_ANSI_X))
        XCTAssertEqual(GlobalHotKey.HotKey.sessionToggle.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalHotKey.HotKey.killSwitch.modifiers, UInt32(cmdKey) | UInt32(shiftKey))
    }
    func testActionRawValuesAreStableAndUnique() {
        let rawValues = GlobalHotKey.Action.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
        XCTAssertEqual(GlobalHotKey.Action(rawValue: 2), .killSwitch)
    }
}
