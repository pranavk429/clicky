import XCTest
@testable import ClickySafety
final class PendingActionGateTests: XCTestCase {
    private func deletion() -> PendingActionGate.PendingAction {
        .init(description: "Delete note 'Project'", tier: .irreversible, anchors: ["Trash", "Delete", "Project"])
    }
    private func payment() -> PendingActionGate.PendingAction {
        .init(description: "Confirm payment of ₹500", tier: .financial, anchors: ["pay"], expectedAmount: 500)
    }
    func testDefaultTimeoutAndFloor() async {
        let gate = PendingActionGate()
        let initial = await gate.effectiveTimeout; XCTAssertEqual(initial, 10)
        let initFloored = await PendingActionGate(timeout: 2).effectiveTimeout; XCTAssertEqual(initFloored, 8)
        await gate.setTimeout(4)
        let floored = await gate.effectiveTimeout; XCTAssertEqual(floored, 8)   // WCAG 2.2.1 floor (errata C2)
        await gate.setTimeout(12)
        let raised = await gate.effectiveTimeout; XCTAssertEqual(raised, 12)
    }
    func testCountdownStartsAtTurnComplete() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(deletion())
        clock.advance(30)
        let idle = await gate.tick(); XCTAssertEqual(idle, .idle)               // no countdown before turnComplete
        await gate.promptTurnComplete()
        clock.advance(4)
        let mid = await gate.tick(); XCTAssertEqual(mid, .counting(remaining: 6))
        clock.advance(7)
        let expired = await gate.tick(); XCTAssertEqual(expired, .expired)
        let state = await gate.state
        guard case .cancelled(_, .timeout) = state else { return XCTFail("expected timeout") }
    }
    func testExpiringSoonAnnouncedOnce() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(deletion()); await gate.promptTurnComplete()
        clock.advance(7.5)
        let soon = await gate.tick(); XCTAssertEqual(soon, .expiringSoon(remaining: 2.5))
        let again = await gate.tick(); XCTAssertEqual(again, .counting(remaining: 2.5))
    }
    func testNegationCancelsAnyTime() async {
        let gate = PendingActionGate()
        await gate.present(deletion())
        let beforePrompt = await gate.userSpoke("ruko")     // negation outranks everything
        XCTAssertEqual(beforePrompt, .cancelled(.negation))
        await gate.present(deletion()); await gate.promptTurnComplete()
        let mixed = await gate.userSpoke("haan nahi ruko")  // negation-first policy
        XCTAssertEqual(mixed, .cancelled(.negation))
        await gate.present(deletion()); await gate.promptTurnComplete()
        let marathi = await gate.userSpoke("नको, थांब")
        XCTAssertEqual(marathi, .cancelled(.negation))
    }
    func testTierThreeNeedsAffirmativeAndEcho() async {
        let gate = PendingActionGate()
        await gate.present(deletion()); await gate.promptTurnComplete()
        let noEcho = await gate.userSpoke("haan"); XCTAssertEqual(noEcho, .ignored("no action echo"))
        let noAffirmative = await gate.userSpoke("trash karo"); XCTAssertEqual(noAffirmative, .ignored("no affirmative"))
        let accepted = await gate.userSpoke("Yes, delete it")   // echoes the action anchor
        XCTAssertEqual(accepted, .accepted)
        let state = await gate.state
        guard case .arming = state else { return XCTFail("expected arming") }
    }
    func testHindiAndMarathiConfirmations() async {
        let gate = PendingActionGate()
        await gate.present(.init(description: "ट्रैश में भेजो", tier: .irreversible, anchors: ["ट्रैश"]))
        await gate.promptTurnComplete()
        let hindi = await gate.userSpoke("हाँ, ट्रैश करो"); XCTAssertEqual(hindi, .accepted)
        await gate.present(.init(description: "ट्रॅश मध्ये टाका", tier: .irreversible, anchors: ["ट्रॅश"]))
        await gate.promptTurnComplete()
        let marathi = await gate.userSpoke("होय, ट्रॅश करा"); XCTAssertEqual(marathi, .accepted)
    }
    func testEchoGateBlocksWhileSpeaking() async {
        let gate = PendingActionGate()
        await gate.present(deletion()); await gate.promptTurnComplete()
        await gate.speakerActive(true)
        let blocked = await gate.userSpoke("haan trash karo"); XCTAssertEqual(blocked, .ignored("echo gate not clear"))
        await gate.speakerActive(false)
        let accepted = await gate.userSpoke("haan trash karo"); XCTAssertEqual(accepted, .accepted)
    }
    func testFinancialLockAmountAndDigits() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(payment()); await gate.promptTurnComplete()
        clock.advance(1)
        let locked = await gate.userSpoke("confirm paanch sau")
        XCTAssertEqual(locked, .ignored("financial lock"))      // 3 s lock after the read-back
        clock.advance(3)
        let wrong = await gate.userSpoke("confirm paanch hazaar")
        XCTAssertEqual(wrong, .ignored("amount mismatch"))
        clock.advance(1)
        let exact = await gate.userSpoke("हाँ ५००"); XCTAssertEqual(exact, .accepted)   // Devanagari digits
    }
    func testSpeechPausesCountdown() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(deletion()); await gate.promptTurnComplete()
        clock.advance(9)
        await gate.userSpeechStarted()
        clock.advance(3)
        let paused = await gate.tick()
        XCTAssertEqual(paused, .expiringSoon(remaining: 1))     // frozen, not expired
        let accepted = await gate.userSpoke("haan trash karo")  // speech end extends the window
        XCTAssertEqual(accepted, .accepted)
    }
    func testArmWindowAndRevalidation() async {
        let gate = PendingActionGate()
        let action = deletion()
        await gate.present(action); await gate.promptTurnComplete()
        _ = await gate.userSpoke("haan trash karo")
        let changed = await gate.awaitArmAndRevalidate(id: action.id) { _ in false }
        XCTAssertEqual(changed, .abort(.targetChanged))         // TOCTOU: fail closed
        await gate.present(action); await gate.promptTurnComplete()
        _ = await gate.userSpoke("haan trash karo")
        let started = Date()
        let executed = await gate.awaitArmAndRevalidate(id: action.id) { _ in true }
        XCTAssertEqual(executed, .execute(action))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), PendingActionGate.armWindow)
    }
    func testKillAndNegationDuringArmWindow() async {
        let gate = PendingActionGate()
        let action = deletion()
        await gate.present(action); await gate.promptTurnComplete()
        _ = await gate.userSpoke("haan trash karo")
        await gate.cancel()                                     // kill switch inside the arm window
        let killed = await gate.awaitArmAndRevalidate(id: action.id) { _ in true }
        XCTAssertEqual(killed, .abort(.killed))
        await gate.present(action); await gate.promptTurnComplete()
        _ = await gate.userSpoke("haan trash karo")
        _ = await gate.userSpoke("ruko")                        // negation inside the arm window
        let negated = await gate.awaitArmAndRevalidate(id: action.id) { _ in true }
        XCTAssertEqual(negated, .abort(.negation))
    }
}
