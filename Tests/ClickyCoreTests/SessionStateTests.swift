// Tests/ClickyCoreTests/SessionStateTests.swift
import XCTest
@testable import ClickyCore
final class SessionStateTests: XCTestCase {
    func testLifecycle() {
        var m = SessionStateMachine()
        XCTAssertEqual(m.apply(.startRequested), .listening)
        XCTAssertEqual(m.apply(.connectionLost(reason: "goAway")), .reconnecting(reason: "goAway"))
        XCTAssertEqual(m.apply(.connectionRestored), .listening)
        XCTAssertEqual(m.apply(.stopRequested(.killSwitch)), .stopped(reason: .killSwitch))
        XCTAssertEqual(m.apply(.startRequested), .listening)
    }
    func testInvalidTransitionsAreIgnored() {
        var m = SessionStateMachine()
        XCTAssertEqual(m.apply(.connectionLost(reason: "drop")), .idle)
        XCTAssertEqual(m.apply(.connectionRestored), .idle)
        XCTAssertEqual(m.apply(.stopRequested(.userToggle)), .idle)
        XCTAssertFalse(SessionState.idle.isActive)
        XCTAssertTrue(SessionState.listening.isActive)
        XCTAssertTrue(SessionState.reconnecting(reason: "x").isActive)
    }
}
