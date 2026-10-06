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
    func testTierThreeNeedsAnAffirmativeAfterThePrompt() async {
        let gate = PendingActionGate()
        await gate.present(deletion()); await gate.promptTurnComplete()
        let noAffirmative = await gate.userSpoke("trash karo"); XCTAssertEqual(noAffirmative, .ignored("no affirmative"))
        // Spec §4.4 script: "Say Haan to confirm" — a bare affirmative after the
        // completed naming prompt must confirm (the earlier anchor-echo
        // requirement was stricter than the spec and silently ignored "haan").
        let accepted = await gate.userSpoke("haan")
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
    func testEarlyAffirmativeLatchesAndArmsOnPromptCompletion() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        let action = deletion()
        await gate.present(action)
        clock.advance(2)
        let early = await gate.userSpoke("haan")
        XCTAssertEqual(early, .ignored("early affirmative latched until the prompt completes"))
        clock.advance(1)
        let completed = await gate.promptTurnComplete()
        XCTAssertTrue(completed)
        let state = await gate.state
        guard case .arming(let armed, let confirmedAt) = state else { return XCTFail("expected arming") }
        XCTAssertEqual(armed, action)
        XCTAssertEqual(confirmedAt, clock.now)      // the arm window starts at prompt completion
        clock.advance(PendingActionGate.armWindow)
        let executed = await gate.awaitArmAndRevalidate(id: action.id) { _ in true }
        XCTAssertEqual(executed, .execute(action))
    }
    func testEarlyAffirmativeDroppedWhileSpeakerActive() async {
        let gate = PendingActionGate()
        await gate.present(deletion())
        await gate.speakerActive(true)
        let dropped = await gate.userSpoke("haan")
        XCTAssertEqual(dropped, .ignored("echo gate not clear"))
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
        let state = await gate.state
        guard case .awaitingConfirmation = state else { return XCTFail("expected awaitingConfirmation") }
        await gate.speakerActive(false)
        let accepted = await gate.userSpoke("haan")
        XCTAssertEqual(accepted, .accepted)
    }
    func testEarlyAffirmativeDroppedForFinancialAction() async {
        let gate = PendingActionGate()
        await gate.present(payment())
        let dropped = await gate.userSpoke("haan paanch sau")
        XCTAssertEqual(dropped, .ignored("prompt not finished"))
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
        let state = await gate.state
        guard case .awaitingConfirmation = state else { return XCTFail("expected awaitingConfirmation") }
    }
    func testStaleEarlyAffirmativeIsDropped() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })    // 10 s timeout
        await gate.present(deletion())
        _ = await gate.userSpoke("haan")
        clock.advance(11)                                   // latch older than the timeout
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
        let state = await gate.state
        guard case .awaitingConfirmation = state else { return XCTFail("expected awaitingConfirmation") }
    }
    func testNegationClearsEarlyLatch() async {
        let gate = PendingActionGate()
        await gate.present(deletion())
        _ = await gate.userSpoke("haan")
        let cancelled = await gate.userSpoke("ruko")
        XCTAssertEqual(cancelled, .cancelled(.negation))
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
        let state = await gate.state
        guard case .cancelled(_, .negation) = state else { return XCTFail("expected negation cancel") }
    }
    func testVoiceEarlyLatchRecordsSource() async {
        let gate = PendingActionGate()
        let initial = await gate.earlyLatchSource
        XCTAssertNil(initial)
        await gate.present(deletion())
        _ = await gate.userSpoke("haan")
        let source = await gate.earlyLatchSource
        XCTAssertEqual(source, .voice)
    }
    func testDirectEarlyLatchRecordsSource() async {
        let gate = PendingActionGate()
        await gate.present(deletion())
        let latched = await gate.userConfirmed()
        XCTAssertEqual(latched, .latched)
        let source = await gate.earlyLatchSource
        XCTAssertEqual(source, .direct)
    }
    func testEarlyLatchSourceClearedOnConsumption() async {
        let gate = PendingActionGate()
        await gate.present(deletion())
        _ = await gate.userSpoke("haan")
        let completed = await gate.promptTurnComplete()
        XCTAssertTrue(completed)
        let source = await gate.earlyLatchSource
        XCTAssertNil(source)                        // consumed with the latch
    }
    func testEarlyLatchSourceClearedWhenStaleLatchIsDropped() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(deletion())
        _ = await gate.userSpoke("haan")
        clock.advance(11)                           // latch older than the timeout
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
        let source = await gate.earlyLatchSource
        XCTAssertNil(source)
    }
    func testEarlyLatchSourceClearedOnPresentNegationAndCancel() async {
        let gate = PendingActionGate()
        let action = deletion()
        await gate.present(action)
        _ = await gate.userSpoke("haan")
        await gate.present(action)                  // supersede
        let afterPresent = await gate.earlyLatchSource
        XCTAssertNil(afterPresent)
        _ = await gate.userSpoke("haan")
        _ = await gate.userSpoke("ruko")            // negation
        let afterNegation = await gate.earlyLatchSource
        XCTAssertNil(afterNegation)
        await gate.present(action)
        _ = await gate.userConfirmed()              // direct latch
        await gate.cancel()                         // kill switch
        let afterCancel = await gate.earlyLatchSource
        XCTAssertNil(afterCancel)
    }
    func testPromptTurnCompleteReturnsFalseWithoutALatch() async {
        let gate = PendingActionGate()
        let idle = await gate.promptTurnComplete(); XCTAssertFalse(idle)
        await gate.present(deletion())
        let first = await gate.promptTurnComplete(); XCTAssertFalse(first)
        let second = await gate.promptTurnComplete(); XCTAssertFalse(second)    // already awaiting confirmation
    }
    func testDirectConfirmationAcceptsAndStillRevalidates() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        let action = deletion()
        await gate.present(action)
        _ = await gate.promptTurnComplete()
        let decision = await gate.userConfirmed()
        XCTAssertEqual(decision, .accepted)
        let state = await gate.state
        guard case .arming(let armed, let confirmedAt) = state else { return XCTFail("expected arming") }
        XCTAssertEqual(armed, action)
        XCTAssertEqual(confirmedAt, clock.now)
        clock.advance(PendingActionGate.armWindow)
        let aborted = await gate.awaitArmAndRevalidate(id: action.id) { _ in false }
        XCTAssertEqual(aborted, .abort(.targetChanged))     // TOCTOU still applies to direct input
    }
    func testDirectConfirmationRespectsFinancialLock() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(payment())
        _ = await gate.promptTurnComplete()
        clock.advance(1)
        let locked = await gate.userConfirmed()
        XCTAssertEqual(locked, .ignored("financial lock"))
        clock.advance(3)                                    // past the 3 s read-back lock
        let accepted = await gate.userConfirmed()
        XCTAssertEqual(accepted, .accepted)
        let state = await gate.state
        guard case .arming = state else { return XCTFail("expected arming") }
    }
    func testDirectConfirmationLatchesEarlyAndArmsOnPromptCompletion() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        let action = deletion()
        await gate.present(action)
        let latched = await gate.userConfirmed()
        XCTAssertEqual(latched, .latched)
        let completed = await gate.promptTurnComplete()
        XCTAssertTrue(completed)
        let state = await gate.state
        guard case .arming(let armed, _) = state else { return XCTFail("expected arming") }
        XCTAssertEqual(armed, action)
    }
    func testDirectConfirmationDropsFinancialEarlyTap() async {
        let gate = PendingActionGate()
        await gate.present(payment())
        let decision = await gate.userConfirmed()
        XCTAssertEqual(decision, .ignored("financial action requires the amount read-back"))
        let completed = await gate.promptTurnComplete()
        XCTAssertFalse(completed)
    }
    func testDirectConfirmationAfterTimeoutIsIgnored() async {
        let clock = TestClock()
        let gate = PendingActionGate(now: { clock.now })
        await gate.present(deletion())
        _ = await gate.promptTurnComplete()
        clock.advance(11)
        _ = await gate.tick()                               // countdown driver expires it first
        let afterTick = await gate.userConfirmed()
        XCTAssertEqual(afterTick, .ignored("no pending action"))
        // Even when tick() has not run yet, a late tap must fail closed.
        let gate2 = PendingActionGate(now: { clock.now })
        await gate2.present(deletion())
        _ = await gate2.promptTurnComplete()
        clock.advance(11)
        let late = await gate2.userConfirmed()
        XCTAssertEqual(late, .ignored("expired"))
        let state = await gate2.state
        guard case .cancelled(_, .timeout) = state else { return XCTFail("expected timeout") }
    }
    func testDirectCancellation() async {
        let gate = PendingActionGate()
        let nothing = await gate.userCancelled(); XCTAssertFalse(nothing)
        let action = deletion()
        await gate.present(action)
        let duringPrompt = await gate.userCancelled(); XCTAssertTrue(duringPrompt)
        let state = await gate.state
        guard case .cancelled(_, .negation) = state else { return XCTFail("expected negation") }
        let completed = await gate.promptTurnComplete(); XCTAssertFalse(completed)
        // A latched early tap is cancelled too.
        await gate.present(action)
        _ = await gate.userConfirmed()
        let latched = await gate.userCancelled(); XCTAssertTrue(latched)
        // Cancellation inside the arm window still wins.
        await gate.present(action)
        _ = await gate.promptTurnComplete()
        _ = await gate.userSpoke("haan")
        let armed = await gate.userCancelled(); XCTAssertTrue(armed)
        let aborted = await gate.awaitArmAndRevalidate(id: action.id) { _ in true }
        XCTAssertEqual(aborted, .abort(.negation))
    }
}
