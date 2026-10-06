import ClickyGemini
import ClickySafety
import XCTest
@testable import ClickyApp

// Task T-CARD-WIRING: the on-screen confirmation card flows through
// `GateAdapter` into the real `PendingActionGate`. Every accepted path still
// runs the gate's arm window + TOCTOU revalidation before the `arm`
// continuation resumes; a card decision never executes on its own.

final class GateAdapterTests: XCTestCase {

    private func makeRequest(tier: RiskTier = .irreversible) -> PendingConfirmationRequest {
        PendingConfirmationRequest(actionID: UUID(), tier: tier, summary: "Delete the project notes",
                                   amount: nil, timeoutSeconds: PendingActionGate.minimumTimeout)
    }

    /// Waits until the adapter's `arm` call has presented to the gate, then lets
    /// the adapter register its continuation (which happens immediately after
    /// `present` returns, with no suspension in between). Real time is the
    /// documented fallback for this seam; the gate's own arm window is real time
    /// too.
    private func waitUntilArmed(_ gate: PendingActionGate) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if case .idle = await gate.state {
                try? await Task.sleep(nanoseconds: 5_000_000)
            } else {
                break
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    /// An early voice affirmative is latched by the gate and consumed by
    /// `markPromptTurnComplete()`, which must run the arm window and resolve the
    /// `arm` continuation as `.confirmed(.voiceTranscript)` — not sit until the
    /// timeout expires.
    func testEarlyVoiceAffirmativeResolvesAfterPromptTurnComplete() async {
        let gate = PendingActionGate(timeout: PendingActionGate.minimumTimeout)
        let adapter = GateAdapter(gate: gate)
        async let decision = adapter.arm(makeRequest())
        await waitUntilArmed(gate)
        await adapter.submitVoiceTranscript("Haan")
        await adapter.markPromptTurnComplete()
        let resolved = await decision
        XCTAssertEqual(resolved, .confirmed(source: .voiceTranscript))
    }

    /// A card confirmation after the prompt finished still runs the arm window +
    /// revalidation and resolves as `.confirmed(.switchControl)`.
    func testCardConfirmationAfterPromptResolvesAsSwitchControl() async {
        let gate = PendingActionGate(timeout: PendingActionGate.minimumTimeout)
        let adapter = GateAdapter(gate: gate)
        async let decision = adapter.arm(makeRequest())
        await waitUntilArmed(gate)
        await adapter.markPromptTurnComplete()
        await adapter.submitCardDecision(confirmed: true)
        let resolved = await decision
        XCTAssertEqual(resolved, .confirmed(source: .switchControl))
    }

    /// A card cancellation resolves the pending arm as `.cancelled` immediately
    /// (nothing will execute, so no arm window is needed).
    func testCardCancellationResolvesCancelled() async {
        let gate = PendingActionGate(timeout: PendingActionGate.minimumTimeout)
        let adapter = GateAdapter(gate: gate)
        async let decision = adapter.arm(makeRequest())
        await waitUntilArmed(gate)
        await adapter.submitCardDecision(confirmed: false)
        let resolved = await decision
        XCTAssertEqual(resolved, .cancelled(reason: "switch control"))
    }

    /// Card input with no pending action is a no-op: no crash, no resume (there
    /// is no pending continuation), and no gate state is created.
    func testCardDecisionWithoutPendingActionIsIgnored() async {
        let gate = PendingActionGate(timeout: PendingActionGate.minimumTimeout)
        let adapter = GateAdapter(gate: gate)
        await adapter.submitCardDecision(confirmed: true)
        await adapter.submitCardDecision(confirmed: false)
        let state = await gate.state
        XCTAssertEqual(state, .idle, "an unsolicited card decision must not create gate state")
    }

    /// A card tap that arrives while the model is still speaking the prompt is
    /// latched by the gate; `submitCardDecision` is a no-op and the pending
    /// `markPromptTurnComplete()` must arm and resolve it instead of letting it
    /// time out. The gate does not track which local channel latched, so the
    /// source is `.voiceTranscript`.
    func testEarlyCardTapLatchesUntilPromptTurnComplete() async {
        let gate = PendingActionGate(timeout: PendingActionGate.minimumTimeout)
        let adapter = GateAdapter(gate: gate)
        async let decision = adapter.arm(makeRequest())
        await waitUntilArmed(gate)
        await adapter.submitCardDecision(confirmed: true)
        let latchedState = await gate.state
        guard case .awaitingTurnComplete = latchedState else {
            return XCTFail("the early tap should latch in awaitingTurnComplete, got \(latchedState)")
        }
        await adapter.markPromptTurnComplete()
        let resolved = await decision
        XCTAssertEqual(resolved, .confirmed(source: .voiceTranscript))
    }
}
