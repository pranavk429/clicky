import ClickyCore
import ClickyGemini
import ClickyOverlay
import ClickySafety
import CoreGraphics
import XCTest
@testable import ClickyApp

struct TestLedger: IntentLedgerPort {
    func recordVoiceUtterance(_ text: String, at date: Date) async {}
    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool { true }
}

/// Records every ledger write in order, so the transcription-aggregation tests
/// can distinguish per-fragment records from the once-per-turn joined record.
actor RecordingLedger: IntentLedgerPort {
    private(set) var utterances: [String] = []
    func recordVoiceUtterance(_ text: String, at date: Date) async { utterances.append(text) }
    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool { true }
    func waitForUtteranceCount(_ count: Int, timeout: TimeInterval) async -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while utterances.count < count && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return utterances
    }
}

struct TestRisk: RiskClassifyingPort {
    func classify(kind: ClickyActionKind, text: String?, targetTitle: String?, targetSubrole: String?,
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
    private(set) var promptTurnCompletes = 0

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
    func submitCardDecision(confirmed: Bool) async {
        let decision: ConfirmationDecision = confirmed
            ? .confirmed(source: .switchControl)
            : .cancelled(reason: "switch control")
        pending?.resume(returning: decision)
        pending = nil
    }
    func markPromptTurnComplete() async { promptTurnCompletes += 1 }
    /// Waits until the scripted turnComplete reached the gate, which (by the
    /// coordinator's ordering) means any joined-utterance write already landed.
    func waitForPromptTurnCompletes(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while promptTurnCompletes < count && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return promptTurnCompletes >= count
    }
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

/// Audio spy that retains `onFrame`, so a test can emit fake mic frames while
/// the Live handshake is parked (the deaf-window buffering tests).
actor EmittingAudio: AudioSessionPort {
    private(set) var starts = 0
    private(set) var stops = 0
    private var onFrame: (@Sendable ([Int16]) -> Void)?

    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {
        starts += 1
        self.onFrame = onFrame
    }
    func stop() async { stops += 1; onFrame = nil }
    func emit(_ samples: [Int16]) { onFrame?(samples) }
    func beginPlaybackTurn() async {}
    func enqueueModelAudio(_ base64Chunks: [String]) async {}
    func stopPlaybackNow() async {}
}

/// Transport whose setup handshake parks on the gate until the test opens it, so
/// capture ordering and the pre-readiness buffer can be observed mid-handshake.
/// With `failAfterGate` the handshake fails once released. `audioPayloads()`
/// extracts the realtimeInput.audio PCM (little-endian) frames in send order.
actor GatedHandshakeTransport: GeminiTransport {
    private let gate: AsyncGate
    private let failAfterGate: Bool
    private var sentFrames: [Data] = []
    private var closed = false
    private(set) var deliveredSetup = false

    init(gate: AsyncGate, failAfterGate: Bool = false) {
        self.gate = gate
        self.failAfterGate = failAfterGate
    }

    func connect() async throws {}
    func send(_ data: Data) async throws {
        guard !closed else { throw GeminiTransportError.closed }
        sentFrames.append(data)
    }
    func receive() async throws -> Data {
        await gate.wait()
        if failAfterGate { throw TestError.boom }
        guard !closed else { throw GeminiTransportError.closed }
        deliveredSetup = true
        return Data(#"{"setupComplete":{}}"#.utf8)
    }
    func close() async { closed = true }

    /// Realtime audio PCM payloads in transmission order.
    func audioPayloads() -> [Data] {
        sentFrames.compactMap { data in
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let realtime = root["realtimeInput"] as? [String: Any],
                  let audio = realtime["audio"] as? [String: Any],
                  let base64 = audio["data"] as? String else { return nil }
            return Data(base64Encoded: base64)
        }
    }

    func waitForAudioPayloads(_ count: Int, timeout: TimeInterval = 2) async -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)
        while audioPayloads().count < count && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return audioPayloads()
    }
}

/// Records `submitCardDecision` calls (and nothing else) so the card-wiring test
/// can assert the exact decisions the overlay buttons deliver.
actor RecordingGate: ConfirmationGatingPort {
    private(set) var cardDecisions: [Bool] = []
    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision { .expired }
    func submitVoiceTranscript(_ text: String) async {}
    func submitModelDecision(confirmed: Bool, echo: String) async {}
    func submitCardDecision(confirmed: Bool) async { cardDecisions.append(confirmed) }
    func markPromptTurnComplete() async {}
    func waitForCardDecisions(_ count: Int, timeout: TimeInterval = 2) async -> [Bool] {
        let deadline = Date().addingTimeInterval(timeout)
        while cardDecisions.count < count && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return cardDecisions
    }
}

/// Ordered, thread-safe recorder for `.clickyModelActivityChanged` posts. The
/// observer runs synchronously on the posting thread (queue: nil), which is the
/// main actor for every post the session makes.
final class ActivityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CompanionActivity] = []
    private var observer: NSObjectProtocol?

    func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: .clickyModelActivityChanged, object: nil, queue: nil) { [weak self] note in
                guard let activity = note.object as? CompanionActivity else { return }
                self?.record(activity)
            }
    }

    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    var activities: [CompanionActivity] { lock.withLock { storage } }

    func waitForCount(_ count: Int, timeout: TimeInterval = 2) async -> [CompanionActivity] {
        let deadline = Date().addingTimeInterval(timeout)
        while activities.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return activities
    }

    private func record(_ activity: CompanionActivity) { lock.withLock { storage.append(activity) } }
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

/// Records the stop reasons a `KillSwitchAdapter` delivers through `onStop`.
actor StopRecorder {
    private(set) var reasons: [StopReason] = []
    func record(_ reason: StopReason) { reasons.append(reason) }
    func waitForCount(_ count: Int, timeout: TimeInterval) async -> [StopReason] {
        let deadline = Date().addingTimeInterval(timeout)
        while reasons.count < count && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return reasons
    }
}

/// Audio spy that records whether the stop-signal observer was already registered
/// when `audio.start` ran (so a connect-window breaker escalation cannot be dropped).
actor OrderingAudio: AudioSessionPort {
    private let stopSignal: TestStopSignal
    private(set) var stopRegisteredBeforeStart = false

    init(stopSignal: TestStopSignal) { self.stopSignal = stopSignal }

    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {
        stopRegisteredBeforeStart = await stopSignal.starts >= 1
    }
    func stop() async {}
    func beginPlaybackTurn() async {}
    func enqueueModelAudio(_ base64Chunks: [String]) async {}
    func stopPlaybackNow() async {}
}

/// Stop signal whose `start()` parks, so a test can stop the coordinator inside the
/// early-registration window (after the client is built, before it connects).
actor GatedStopSignal: StopSignalPort {
    private let gate: AsyncGate
    private(set) var starts = 0
    private(set) var stops = 0

    init(gate: AsyncGate) { self.gate = gate }

    func start(onStop: @escaping @Sendable (StopReason) -> Void) async {
        starts += 1
        await gate.wait()   // reentrant: stopSignal.stop() still runs while parked here
    }
    func stop() async { stops += 1 }
    func resetLatch() async {}
    func triggerBargeIn(onset: ContinuousClock.Instant) async {}
}

/// Counts transport-factory invocations, i.e. whether the client attempted to connect.
actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Transport whose `close()` parks, so an older stop can be held mid-teardown while a
/// newer start lands.
actor BlockingCloseTransport: GeminiTransport {
    private let gate: AsyncGate
    private var deliveredSetup = false

    init(gate: AsyncGate) { self.gate = gate }

    func connect() async throws {}
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data {
        if !deliveredSetup {
            deliveredSetup = true
            return Data(#"{"setupComplete":{}}"#.utf8)
        }
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
        throw GeminiTransportError.closed
    }
    func close() async { await gate.wait() }
}

/// Vends the blocking-close transport for the first start and a normal mock after.
actor TransportVendor {
    private let closeGate: AsyncGate
    private(set) var calls = 0

    init(closeGate: AsyncGate) { self.closeGate = closeGate }

    func make() throws -> any GeminiTransport {
        calls += 1
        if calls == 1 { return BlockingCloseTransport(gate: closeGate) }
        return try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
    }
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
    /// superseded start installs no session state, tears its early capture down, and a
    /// later start works normally. Capture now opens BEFORE the handshake (the
    /// deaf-window fix), so a superseding stop must stop it — it can no longer be 0.
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
        let audioStops = await audio.stops
        let signalStarts = await stopSignal.starts
        let signalStops = await stopSignal.stops
        XCTAssertEqual(audioStarts, 1, "capture opens before the handshake")
        XCTAssertEqual(audioStops, 1, "the superseding stop must stop the early capture")
        // The stop observer is registered BEFORE live.start() (so a connect-window
        // breaker escalation is never dropped); the superseding stop() tears it down.
        XCTAssertEqual(signalStarts, 1, "the observer is registered early, before the client goes live")
        XCTAssertEqual(signalStops, 1, "the superseding stop must tear the observer down")

        // The same coordinator starts cleanly afterwards.
        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
        let audioStartsAfter = await audio.starts
        let signalStartsAfter = await stopSignal.starts
        XCTAssertEqual(audioStartsAfter, 2, "the fresh start opens capture once more")
        XCTAssertEqual(signalStartsAfter, 2, "the fresh start registers the observer again")
        await coordinator.stop(reason: .userToggle)
        XCTAssertFalse(coordinator.isRunning)
    }

    /// Issue 1: the stop observer must exist before the client can process a tool call,
    /// so a breaker escalation in the connect window (after `live.start()`, before
    /// `audio.start`) is never posted to nobody.
    func testStopObserverRegisteredBeforeAudioStart() async throws {
        let stopSignal = TestStopSignal()
        let audio = OrderingAudio(stopSignal: stopSignal)
        let mock = try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal, transportFactory: { mock })

        await coordinator.start()

        let registered = await audio.stopRegisteredBeforeStart
        XCTAssertTrue(registered,
                      "the stop observer must be registered before audio starts, or a connect-window escalation is dropped")
        await coordinator.stop(reason: .userToggle)
    }

    /// Issue 2: a prior voice barge-in latches the manager; a later breaker trip must
    /// still deliver the session stop unconditionally.
    func testBreakerEscalationDeliversAfterBargeInLatch() async throws {
        let recorder = StopRecorder()
        let adapter = KillSwitchAdapter(playbackStop: {}, releaseInput: {})
        await adapter.start { reason in Task { await recorder.record(reason) } }
        await adapter.triggerBargeIn(onset: ContinuousClock.now)   // latches the same manager
        await adapter.triggerKillSwitch(source: "circuit_breaker")

        let reasons = await recorder.waitForCount(1, timeout: 2)
        XCTAssertEqual(reasons, [.killSwitch], "a breaker trip must not be swallowed by a prior barge-in latch")
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

    /// FIX 2 (live logs: `not_authorized (rejected intent: Open a new tab)`):
    /// the Live API streams transcription in fragments, so a multi-fragment turn
    /// must also record the JOINED utterance once — in addition to the existing
    /// per-fragment records — or the model's clean paraphrase cannot match the
    /// T10 ledger.
    func testMultiFragmentTurnRecordsJoinedUtteranceOnce() async throws {
        let ledger = RecordingLedger()
        let gate = TestGateBridge()
        let json = try Self.transcriptionScenarioJSON(fragments: ["Open a", "new tab"], turnComplete: true)
        let mock = try MockSession(scenarioJSON: json, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: ledger, risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: gate,
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock }, transcriptionQuietGap: 60)
        await coordinator.start()

        let completed = await gate.waitForPromptTurnCompletes(1)
        XCTAssertTrue(completed, "the scripted turn must complete")
        let utterances = await ledger.utterances
        XCTAssertEqual(utterances, ["Open a", "new tab", "Open a new tab"],
                       "each fragment is recorded, then the joined utterance exactly once")
        await coordinator.stop(reason: .userToggle)
    }

    /// A single-fragment turn must behave exactly as before: one ledger record,
    /// one gate submission, no duplicate joined record.
    func testSingleFragmentTurnIsUnchanged() async throws {
        let ledger = RecordingLedger()
        let gate = TestGateBridge()
        let json = try Self.transcriptionScenarioJSON(fragments: ["Open a new tab"], turnComplete: true)
        let mock = try MockSession(scenarioJSON: json, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: ledger, risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: gate,
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock }, transcriptionQuietGap: 60)
        await coordinator.start()

        let completed = await gate.waitForPromptTurnCompletes(1)
        XCTAssertTrue(completed, "the scripted turn must complete")
        let utterances = await ledger.utterances
        let transcripts = await gate.transcripts
        XCTAssertEqual(utterances, ["Open a new tab"], "a single fragment must not be duplicated as a joined record")
        XCTAssertEqual(transcripts, ["Open a new tab"])
        await coordinator.stop(reason: .userToggle)
    }

    /// The confirmation gate must keep seeing every fragment exactly as before
    /// (its semantics must not change); only the ledger gains the joined record.
    func testGateStillReceivesEveryFragmentExactlyOnce() async throws {
        let ledger = RecordingLedger()
        let gate = TestGateBridge()
        let json = try Self.transcriptionScenarioJSON(fragments: ["Switch", "to browser"], turnComplete: true)
        let mock = try MockSession(scenarioJSON: json, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: ledger, risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: gate,
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock }, transcriptionQuietGap: 60)
        await coordinator.start()

        let completed = await gate.waitForPromptTurnCompletes(1)
        XCTAssertTrue(completed, "the scripted turn must complete")
        let transcripts = await gate.transcripts
        XCTAssertEqual(transcripts, ["Switch", "to browser"],
                       "the gate receives each fragment in order, exactly once")
        await coordinator.stop(reason: .userToggle)
    }

    /// The quiet-gap debounce flushes a multi-fragment turn even when no
    /// `turnComplete` frame arrives (the turn is still open server-side).
    func testQuietGapRecordsJoinedUtteranceWithoutTurnComplete() async throws {
        let ledger = RecordingLedger()
        let json = try Self.transcriptionScenarioJSON(fragments: ["Open a", "new tab"], turnComplete: false)
        let mock = try MockSession(scenarioJSON: json, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: ledger, risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock }, transcriptionQuietGap: 0.25)
        await coordinator.start()

        let utterances = await ledger.waitForUtteranceCount(3, timeout: 2)
        XCTAssertEqual(utterances, ["Open a", "new tab", "Open a new tab"],
                       "the quiet gap must record the joined utterance without turnComplete")
        await coordinator.stop(reason: .userToggle)
    }

    /// Builds a mock scenario from transcription fragments (and an optional
    /// turnComplete frame), encoding the inner server JSON so tests never
    /// hand-escape nested quotes.
    private static func transcriptionScenarioJSON(fragments: [String], turnComplete: Bool) throws -> String {
        struct Frame: Encodable { var afterMs: Int; var json: String }
        struct Scenario: Encodable { var name: String; var frames: [Frame] }
        var frames = [Frame(afterMs: 0, json: #"{"setupComplete":{}}"#)]
        for fragment in fragments {
            let payload: [String: Any] = ["serverContent": ["inputTranscription": ["text": fragment]]]
            let data = try JSONSerialization.data(withJSONObject: payload)
            frames.append(Frame(afterMs: 0, json: String(decoding: data, as: UTF8.self)))
        }
        if turnComplete {
            frames.append(Frame(afterMs: 0, json: #"{"serverContent":{"turnComplete":true}}"#))
        }
        let scenario = Scenario(name: "transcription", frames: frames)
        return String(decoding: try JSONEncoder().encode(scenario), as: UTF8.self)
    }

    /// Decodes the shipped mock scenario into server messages so the test compares the
    /// exact scripted strings rather than hard-coded copies.
    private static func scenarioMessages() throws -> [GeminiServerMessage] {
        let json = try SessionCoordinator.demoCancelScenarioJSON()
        let scenario = try JSONDecoder().decode(MockSession.Scenario.self, from: Data(json.utf8))
        return scenario.frames.compactMap { GeminiServerMessage.decode(from: Data($0.json.utf8)) }
    }

    /// Issue 1: a stop that lands inside the early-registration window must stop the
    /// stale start from connecting at all (no orphaned client with a live toolHandler).
    func testStaleStartDoesNotConnectAfterStopDuringRegistration() async throws {
        let gate = AsyncGate()
        let stopSignal = GatedStopSignal(gate: gate)
        let counter = CallCounter()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: SpyAudio(), stopSignal: stopSignal,
            transportFactory: {
                await counter.increment()
                return try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
            })

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()                 // start() parked in stopSignal.start()
        await coordinator.stop(reason: .userToggle)
        await gate.open()
        await startTask.value

        let factoryCalls = await counter.count
        let starts = await stopSignal.starts
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertNil(coordinator.client)
        XCTAssertEqual(starts, 1, "the stop observer was registered before the client went live")
        XCTAssertEqual(factoryCalls, 0, "a superseded start must not connect the client")
    }

    /// Issue 2: a new start that lands while an older stop is parked mid-teardown must
    /// keep its client/router/observer; the older stop's trailing teardown must bail out.
    func testOlderStopDoesNotClobberNewerSession() async throws {
        let closeGate = AsyncGate()
        let vendor = TransportVendor(closeGate: closeGate)
        let audio = SpyAudio()
        let stopSignal = TestStopSignal()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal,
            transportFactory: { try await vendor.make() })

        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)

        let stopTask = Task { await coordinator.stop(reason: .userToggle) }
        await closeGate.waitForWaiter()            // older stop parked in client.stop

        // A new start lands while the older stop is still tearing down.
        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
        XCTAssertNotNil(coordinator.client, "the new session's client must not be clobbered")
        XCTAssertNotNil(coordinator.router, "the new session's router must not be clobbered")

        await closeGate.open()
        await stopTask.value                       // older stop resumes; must not clobber

        XCTAssertTrue(coordinator.isRunning, "the older stop must not stop the newer session")
        XCTAssertNotNil(coordinator.client)
        XCTAssertNotNil(coordinator.router)
        let signalStops = await stopSignal.stops
        XCTAssertEqual(signalStops, 0, "the older stop must not remove the newer session's observer")

        // The newer session still stops cleanly.
        await coordinator.stop(reason: .userToggle)
        XCTAssertFalse(coordinator.isRunning)
        let audioStops = await audio.stops
        let signalStopsAfter = await stopSignal.stops
        XCTAssertEqual(audioStops, 1, "the newer session tears audio down exactly once")
        XCTAssertEqual(signalStopsAfter, 1)
    }

    // MARK: Deaf-window fix (capture before the Live handshake)

    /// The #1 live failure: everything the user said during the 800–1800 ms
    /// WebSocket handshake was lost because the mic opened last. Capture must be
    /// live while the transport is still completing setup.
    func testMicrophoneCaptureStartsBeforeTheHandshakeCompletes() async throws {
        let gate = AsyncGate()
        let transport = GatedHandshakeTransport(gate: gate)
        let audio = EmittingAudio()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: TestStopSignal(),
            transportFactory: { transport })

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()   // parked inside the setup handshake

        let audioStarts = await audio.starts
        let deliveredSetup = await transport.deliveredSetup
        XCTAssertEqual(audioStarts, 1, "mic capture must open before the setup handshake completes")
        XCTAssertFalse(deliveredSetup, "the handshake is still in flight at this point")

        await gate.open()
        await startTask.value
        XCTAssertTrue(coordinator.isRunning)
        await coordinator.stop(reason: .userToggle)
    }

    /// Frames captured during the handshake are buffered and flushed IN ORDER to
    /// the Live client the moment setup completes; streaming then continues live.
    func testFramesCapturedDuringHandshakeAreFlushedInOrderAfterReady() async throws {
        let gate = AsyncGate()
        let transport = GatedHandshakeTransport(gate: gate)
        let audio = EmittingAudio()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: TestStopSignal(),
            transportFactory: { transport })

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()
        let frames: [[Int16]] = (0..<8).map { [Int16($0), Int16($0 + 1), Int16($0 + 2)] }
        for frame in frames { await audio.emit(frame) }
        await gate.open()
        await startTask.value

        let payloads = await transport.waitForAudioPayloads(frames.count)
        XCTAssertEqual(payloads.count, frames.count,
                       "every frame captured during the handshake must be transmitted once ready")
        XCTAssertEqual(payloads, frames.map(Self.pcmData),
                       "buffered frames must flush in capture order")
        await coordinator.stop(reason: .userToggle)
    }

    /// Failure path: a handshake that fails after capture began must stop the mic
    /// (it must not stay hot) and discard the buffered frames — nothing is sent.
    func testHandshakeFailureStopsCaptureAndDropsBufferedFrames() async throws {
        let gate = AsyncGate()
        let transport = GatedHandshakeTransport(gate: gate, failAfterGate: true)
        let audio = EmittingAudio()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: TestStopSignal(),
            transportFactory: { transport })
        var notices: [String] = []
        coordinator.onNotice = { notices.append($0) }
        let recorder = ActivityRecorder()
        recorder.startObserving()
        defer { recorder.stopObserving() }

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()
        for index in 0..<5 { await audio.emit([Int16(index)]) }
        await gate.open()
        await startTask.value

        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(notices.contains { $0.contains("Session could not start") },
                      "the handshake failure must be surfaced")
        let stops = await audio.stops
        let payloads = await transport.audioPayloads()
        XCTAssertEqual(stops, 1, "the failure path must stop capture — the mic must not stay hot")
        XCTAssertTrue(payloads.isEmpty, "buffered frames must be discarded, never flushed")
        let activities = await recorder.waitForCount(1)
        XCTAssertEqual(activities, [.hidden], "a failed start must hide the companion")
    }

    /// A stop() during the handshake stops capture and discards the buffer; the
    /// session must not flush frames from a superseded attempt.
    func testStopDuringHandshakeStopsCaptureAndDropsBufferedFrames() async throws {
        let gate = AsyncGate()
        let transport = GatedHandshakeTransport(gate: gate)
        let audio = EmittingAudio()
        let stopSignal = TestStopSignal()
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: audio, stopSignal: stopSignal,
            transportFactory: { transport })

        let startTask = Task { await coordinator.start() }
        await gate.waitForWaiter()
        for index in 0..<5 { await audio.emit([Int16(index)]) }
        await coordinator.stop(reason: .userToggle)   // stop wins the race
        await gate.open()
        await startTask.value

        XCTAssertFalse(coordinator.isRunning)
        let stops = await audio.stops
        let payloads = await transport.audioPayloads()
        XCTAssertEqual(stops, 1, "the superseding stop must stop capture")
        XCTAssertTrue(payloads.isEmpty, "the buffer must be discarded, never flushed")
    }

    // MARK: Ambient companion activity (Task T-OVERLAY)

    /// The session posts the companion activity at every turn transition:
    /// listening at start, thinking on the transcription, speaking on the first
    /// model audio chunk, listening again at turnComplete, hidden at stop.
    func testModelActivitySequenceFollowsScriptedTurn() async throws {
        let recorder = ActivityRecorder()
        recorder.startObserving()
        defer { recorder.stopObserving() }
        let mock = try MockSession(scenarioJSON: Self.activityScenarioJSON(), sleeper: RealSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: TestGateBridge(),
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock })

        await coordinator.start()
        let activities = await recorder.waitForCount(4)
        XCTAssertEqual(activities, [.listening, .thinking, .speaking, .listening],
                       "the companion must follow the model through the turn")

        await coordinator.stop(reason: .userToggle)
        let afterStop = await recorder.waitForCount(5)
        XCTAssertEqual(afterStop.last, .hidden, "stopping the session must hide the companion")
    }

    // MARK: On-screen confirmation card wiring (Task T-OVERLAY)

    /// The card buttons must reach the pending-action gate: confirm →
    /// submitCardDecision(true), cancel → submitCardDecision(false).
    func testCardActionRoutesToTheConfirmationGate() async throws {
        let gate = RecordingGate()
        let mock = try MockSession(scenarioJSON: noopScenarioJSON, sleeper: ImmediateSleeper())
        let coordinator = SessionCoordinator(
            ledger: TestLedger(), risk: TestRisk(), screenContext: TestContext(),
            system: TestSystemSpy(), overlay: TestOverlaySpy(), gate: gate,
            audio: SpyAudio(), stopSignal: TestStopSignal(),
            transportFactory: { mock })
        await coordinator.start()

        OverlayWindowController.shared.onCardAction?(.confirm)
        let afterConfirm = await gate.waitForCardDecisions(1)
        XCTAssertEqual(afterConfirm, [true], "a card confirm must reach the gate as confirmed")

        OverlayWindowController.shared.onCardAction?(.cancel)
        let afterCancel = await gate.waitForCardDecisions(2)
        XCTAssertEqual(afterCancel, [true, false], "a card cancel must reach the gate as not confirmed")

        OverlayWindowController.shared.onCardAction = nil
        await coordinator.stop(reason: .userToggle)
    }

    /// Little-endian PCM exactly as `GeminiLiveClient.sendAudioFrame` encodes it,
    /// so the flush test compares transmitted bytes to the emitted samples.
    private static func pcmData(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// A scripted turn with a gap before the first content frame, so the start()
    /// success `.listening` post deterministically precedes the turn's posts.
    private static func activityScenarioJSON() -> String {
        let audioContent: [String: Any] = [
            "serverContent": ["modelTurn": ["parts": [
                ["inlineData": ["mimeType": "audio/pcm;rate=24000",
                                "data": Data([0, 1, 2, 3]).base64EncodedString()]]
            ]]]
        ]
        let audioJSON = (try? JSONSerialization.data(withJSONObject: audioContent))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        struct Frame: Encodable { var afterMs: Int; var json: String }
        struct Scenario: Encodable { var name: String; var frames: [Frame] }
        let frames = [
            Frame(afterMs: 0, json: #"{"setupComplete":{}}"#),
            Frame(afterMs: 300, json: #"{"serverContent":{"inputTranscription":{"text":"Open a new tab"}}}"#),
            Frame(afterMs: 100, json: audioJSON),
            Frame(afterMs: 100, json: #"{"serverContent":{"turnComplete":true}}"#),
        ]
        let scenario = Scenario(name: "activity", frames: frames)
        return (try? JSONEncoder().encode(scenario)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
