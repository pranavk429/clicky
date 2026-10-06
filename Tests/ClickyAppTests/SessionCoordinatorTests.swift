import ClickyCore
import ClickyGemini
import ClickySafety
import CoreGraphics
import XCTest
@testable import ClickyApp

struct TestLedger: IntentLedgerPort {
    func recordVoiceUtterance(_ text: String, at date: Date) async {}
    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool { true }
}

struct TestRisk: RiskClassifyingPort {
    func classify(kind: ClickyActionKind, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier { .irreversible }
}

struct TestContext: ScreenContextProviding {
    func captureContext(reason: String, maxNodes: Int) async -> ScreenContext {
        ScreenContext(applicationName: "Notes", windowTitle: "Notes", elements: [])
    }
}

actor TestSystemSpy: SystemActionPort {
    private(set) var resolves = 0
    private(set) var performs: [ResolvedAction] = []
    func resolve(title: String?, kind: ClickyActionKind) async -> ResolvedTarget? {
        resolves += 1
        return ResolvedTarget(applicationName: "Notes", role: "AXButton", subrole: nil, title: "Project",
                              windowTitle: "Notes", cgFrame: CGRect(x: 20, y: 40, width: 90, height: 24))
    }
    func perform(_ action: ResolvedAction) async -> ActionOutcome {
        performs.append(action)
        return .performed(detail: "test")
    }
}

actor TestOverlaySpy: GhostCursorPort {
    private(set) var presentations: [GhostCursorPresentation] = []
    func present(_ presentation: GhostCursorPresentation) async { presentations.append(presentation) }
}

/// Behaves like the real gate: `arm` waits; the voice transcript decides.
actor TestGateBridge: ConfirmationGatingPort {
    private var pending: CheckedContinuation<ConfirmationDecision, Never>?
    private(set) var armed = 0
    private(set) var transcripts: [String] = []

    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision {
        armed += 1
        return await withCheckedContinuation { continuation in
            if let superseded = pending {
                pending = continuation
                superseded.resume(returning: .cancelled(reason: "superseded"))
            } else {
                pending = continuation
                Task {   // safety valve: never hang a test run
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await self.expire()
                }
            }
        }
    }
    private func expire() { pending?.resume(returning: .expired); pending = nil }
    func submitVoiceTranscript(_ text: String) async {
        transcripts.append(text)
        let lowered = text.lowercased()
        if lowered.contains("cancel") || lowered.contains("ruko") {
            pending?.resume(returning: .cancelled(reason: "negation: \(text)"))
            pending = nil
        }
    }
    func submitModelDecision(confirmed: Bool, echo: String) async {}
    func markPromptTurnComplete() async {}
}

struct TestAudio: AudioSessionPort {
    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {}
    func stop() async {}
    func beginPlaybackTurn() async {}
    func enqueueModelAudio(_ base64Chunks: [String]) async {}
    func stopPlaybackNow() async {}
}

struct TestStopSignal: StopSignalPort {
    func start(onStop: @escaping @Sendable (StopReason) -> Void) async {}
    func stop() async {}
    func resetLatch() async {}
    func triggerBargeIn(onset: ContinuousClock.Instant) async {}
}

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testMockDemoRoutesThroughRouterAndCancelsBeforeExecution() async throws {
        let system = TestSystemSpy()
        let overlay = TestOverlaySpy()
        let gate = TestGateBridge()
        let mock = try MockSession(scenarioJSON: SessionCoordinator.demoCancelScenarioJSON(),
                                   sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: system, overlay: overlay, gate: gate,
            audio: TestAudio(), stopSignal: TestStopSignal(), transportFactory: { mock })
        await coordinator.start()

        let sent = await mock.waitForSent(count: 2, timeout: 6)   // setup + toolResponse
        XCTAssertEqual(sent?.count, 2)
        XCTAssertTrue(sent?.first?.contains("character-for-character") == true,
                      "the real system instruction must be in the setup frame")
        XCTAssertTrue(sent?.last?.contains("cancelled") == true,
                      "the scripted cancel must produce a cancelled tool response")
        let resolves = await system.resolves
        let performs = await system.performs.count
        let armed = await gate.armed
        let transcripts = await gate.transcripts
        XCTAssertEqual(resolves, 1, "the tool call must reach the router and the AX port")
        XCTAssertEqual(performs, 0, "nothing may execute after a cancel")
        XCTAssertEqual(armed, 1)
        // The gate submits every input transcription (the pre-arm "Delete my project
        // note" utterance included); the spoken cancel is the last one it sees.
        XCTAssertEqual(transcripts.last, "No, cancel that!")
        await coordinator.stop(reason: .userToggle)
    }
}
