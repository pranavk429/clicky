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

enum TestError: Error { case boom }

/// Controllable async gate for the stop-during-start test: the transport factory
/// parks on `wait()` until the test opens it.
actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var waiters = 0

    func wait() async {
        if opened { return }
        waiters += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForWaiter() async {
        while waiters == 0 { await Task.yield() }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

let noopScenarioJSON = #"{"name":"noop","frames":[{"afterMs":0,"json":"{\"setupComplete\":{}}"}]}"#

actor SpyAudio: AudioSessionPort {
    private(set) var starts = 0
    private(set) var stops = 0
    private let failOnStart: Bool

    init(failOnStart: Bool = false) { self.failOnStart = failOnStart }

    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {
        starts += 1
        if failOnStart { throw TestError.boom }
    }
    func stop() async { stops += 1 }
    func beginPlaybackTurn() async {}
    func enqueueModelAudio(_ base64Chunks: [String]) async {}
    func stopPlaybackNow() async {}
}

actor TestStopSignal: StopSignalPort {
    private(set) var resets = 0
    private(set) var starts = 0
    private(set) var stops = 0
    func start(onStop: @escaping @Sendable (StopReason) -> Void) async { starts += 1 }
    func stop() async { stops += 1 }
    func resetLatch() async { resets += 1 }
    func triggerBargeIn(onset: ContinuousClock.Instant) async {}
}

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testMockDemoRoutesThroughRouterAndCancelsBeforeExecution() async throws {
        let system = TestSystemSpy()
        let overlay = TestOverlaySpy()
        let gate = TestGateBridge()
        // RealSleeper honours the scenario's afterMs sequencing: the 1500 ms gap
        // before the "No, cancel that!" beat is what guarantees the gate has armed
        // before the cancel arrives (ImmediateSleeper collapses that ordering).
        let mock = try MockSession(scenarioJSON: SessionCoordinator.demoCancelScenarioJSON(),
                                   sleeper: RealSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: system, overlay: overlay, gate: gate,
            audio: SpyAudio(), stopSignal: TestStopSignal(), transportFactory: { mock })
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

    /// The kill-switch latches on the first trigger, so every listening session must
    /// re-arm it (spec §4.4). The registered Carbon chord cannot be exercised headless;
    /// this pins the session seam that the app's `.listening` reset hangs off.
    func testSessionStartReArmsTheStopSignal() async throws {
        let stopSignal = TestStopSignal()
        let scenario = #"{"name":"noop","frames":[{"afterMs":0,"json":"{\"setupComplete\":{}}"}]}"#
        let mock = try MockSession(scenarioJSON: scenario, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: SpyAudio(), stopSignal: stopSignal, transportFactory: { mock })
        await coordinator.start()

        let resets = await stopSignal.resets
        XCTAssertGreaterThanOrEqual(resets, 1, "session start must re-arm the latched kill switch")
        await coordinator.stop(reason: .userToggle)
    }

    /// start/stop is one state machine: a second stop must not re-enter teardown.
    func testDoubleStopIsANoOp() async throws {
        let audio = SpyAudio()
        let stopSignal = TestStopSignal()
        let mock = try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal, transportFactory: { mock })
        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)

        await coordinator.stop(reason: .userToggle)
        await coordinator.stop(reason: .userToggle)   // second stop must be inert

        let audioStops = await audio.stops
        let signalStops = await stopSignal.stops
        XCTAssertEqual(audioStops, 1, "teardown must run exactly once")
        XCTAssertEqual(signalStops, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    /// A stop() that lands while start() is parked in an await is authoritative: the
    /// superseded start must install no audio/kill-switch state, and a later start
    /// must work normally.
    func testStopDuringStartTearsDownAndLaterStartWorks() async throws {
        let gate = AsyncGate()
        let audio = SpyAudio()
        let stopSignal = TestStopSignal()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal,
            transportFactory: { await gate.wait(); return try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper()) })

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()                     // start() is parked in the transport factory
        await coordinator.stop(reason: .userToggle)    // stop wins the race
        await gate.open()
        await startTask.value

        XCTAssertFalse(coordinator.isRunning)
        let audioStarts = await audio.starts
        let signalStarts = await stopSignal.starts
        XCTAssertEqual(audioStarts, 0, "a superseded start must not start audio")
        XCTAssertEqual(signalStarts, 0, "a superseded start must not register the kill switch")

        // The same coordinator starts cleanly afterwards.
        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
        let audioStartsAfter = await audio.starts
        let signalStartsAfter = await stopSignal.starts
        XCTAssertEqual(audioStartsAfter, 1, "a fresh start installs audio exactly once")
        XCTAssertEqual(signalStartsAfter, 1)
        await coordinator.stop(reason: .userToggle)
        XCTAssertFalse(coordinator.isRunning)
    }

    /// An audio (or kill-switch) start failure surfaces a notice and tears the whole
    /// session down rather than leaving a half-started state.
    func testAudioStartFailureNoticesAndTearsDown() async throws {
        let audio = SpyAudio(failOnStart: true)
        let stopSignal = TestStopSignal()
        let mock = try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal, transportFactory: { mock })
        var notices: [String] = []
        coordinator.onNotice = { notices.append($0) }

        await coordinator.start()

        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(notices.contains { $0.contains("Audio or kill switch failed to start") },
                      "a start failure must be surfaced")
        let audioStops = await audio.stops
        let signalStops = await stopSignal.stops
        XCTAssertEqual(audioStops, 1, "the failure path must tear audio down")
        XCTAssertEqual(signalStops, 1, "the failure path must tear the stop signal down")
    }

    /// Pins the mock scenario against the REAL T10 ledger: the scripted `execute_action`
    /// intent must be traceable to the scenario's own transcribed utterance, or the
    /// deferred mock beat returns `not_authorized` and never reaches the confirm/cancel
    /// gate. Both strings are extracted from `demoCancelScenarioJSON()`, so the test
    /// fails if either side (transcription or scripted intent) drifts.
    func testMockScenarioIntentIsTraceableThroughTheRealLedger() async throws {
        let messages = try Self.scenarioMessages()
        let utterance = try XCTUnwrap(messages.compactMap { message -> String? in
            guard case .serverContent(let content) = message else { return nil }
            return content.inputTranscription?.text
        }.first, "the scenario must script a voice utterance")
        let intent = try XCTUnwrap(messages.compactMap { message -> String? in
            guard case .toolCall(let call) = message else { return nil }
            guard case .string(let value)? = call.functionCalls.first?.args?["intent"] else { return nil }
            return value
        }.first, "the scenario must script an execute_action intent")

        let adapter = LedgerAdapter()
        await adapter.recordVoiceUtterance(utterance, at: Date())
        let authorized = await adapter.isTraceableToVoiceIntent(intent, at: Date())
        XCTAssertTrue(authorized,
                      "scripted intent '\(intent)' must be traceable to scripted utterance '\(utterance)' via the real IntentLedger")
    }

    /// Decodes the shipped mock scenario into server messages so the test compares the
    /// exact scripted strings rather than hard-coded copies.
    private static func scenarioMessages() throws -> [GeminiServerMessage] {
        let json = try SessionCoordinator.demoCancelScenarioJSON()
        let scenario = try JSONDecoder().decode(MockSession.Scenario.self, from: Data(json.utf8))
        return scenario.frames.compactMap { GeminiServerMessage.decode(from: Data($0.json.utf8)) }
    }
}
