import ClickyAudio
import ClickyCore
import ClickyGemini
import ClickyInput
import Foundation

/// Session seams the app injects around Chunks 9–10 (fakes in tests).
/// Chunk-13 seams only — `ToolRouter`'s ports are frozen (Chunk 12, Task 12.2).
protocol AudioSessionPort: Sendable {
    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws
    func stop() async
    /// Called at the top of every model turn (§0.4 model-audio wiring).
    func beginPlaybackTurn() async
    /// Base64 24 kHz PCM from `GeminiServerContent.audioBase64Chunks`.
    func enqueueModelAudio(_ base64Chunks: [String]) async
    /// The synchronous barge-in panic path.
    func stopPlaybackNow() async
}

protocol StopSignalPort: Sendable {
    func start(onStop: @escaping @Sendable (StopReason) -> Void) async
    func stop() async
    /// Re-arm the latched kill switch at listening/turn start.
    func resetLatch() async
    func triggerBargeIn(onset: ContinuousClock.Instant) async
}

/// End-to-end wiring (spec §3). `AppState` drives start/stop through
/// `.clickySessionStateChanged`; this object owns the Live client, the router, the
/// audio feed, the kill switch and one `ToolRouter` per session. Mock mode
/// (`CLICKY_MOCK=1`) swaps ONLY the transport: every scripted tool call still flows
/// through `ToolRouter` and the real AX/CGEvent adapters below it (spec §6).
@MainActor
final class SessionCoordinator {
    typealias TransportFactory = @Sendable () async throws -> any GeminiTransport

    let ledger: any IntentLedgerPort
    let risk: any RiskClassifyingPort
    let screenContext: any ScreenContextProviding
    let system: any SystemActionPort
    let overlay: any GhostCursorPort
    let gate: any ConfirmationGatingPort
    let audio: any AudioSessionPort
    let stopSignal: any StopSignalPort
    let warmer: (any ScreenCacheWarming)?
    let transportFactory: TransportFactory
    let confirmationTimeout: TimeInterval

    var onNotice: ((String) -> Void)?
    var onMarker: ((GeminiMarker) -> Void)?
    private(set) var isRunning = false
    private var startGeneration = 0
    private var client: GeminiLiveClient?
    private var router: ToolRouter?
    private var modelTurnActive = false
    private var audioContinuation: AsyncStream<[Int16]>.Continuation?
    private var audioSendTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(ledger: any IntentLedgerPort, risk: any RiskClassifyingPort,
         screenContext: any ScreenContextProviding, system: any SystemActionPort,
         overlay: any GhostCursorPort, gate: any ConfirmationGatingPort,
         audio: any AudioSessionPort, stopSignal: any StopSignalPort,
         warmer: (any ScreenCacheWarming)? = nil,
         transportFactory: @escaping TransportFactory,
         confirmationTimeout: TimeInterval = ToolRouter.defaultConfirmationTimeout) {
        self.ledger = ledger; self.risk = risk; self.screenContext = screenContext
        self.system = system; self.overlay = overlay; self.gate = gate
        self.audio = audio; self.stopSignal = stopSignal; self.warmer = warmer
        self.transportFactory = transportFactory; self.confirmationTimeout = confirmationTimeout
    }

    static let shared: SessionCoordinator = {
        let synthesizer = EventSynthesizer()
        let engine = AudioStreamEngine()
        let ax = AXEngineAdapter(synthesizer: synthesizer)
        return SessionCoordinator(ledger: LedgerAdapter(), risk: RiskAdapter(),
                                  screenContext: ax, system: ax,
                                  overlay: OverlayAdapter(), gate: GateAdapter(),
                                  audio: AudioAdapter(engine: engine),
                                  stopSignal: KillSwitchAdapter(playbackStop: { engine.stopPlaybackNow() }),
                                  warmer: ax,
                                  transportFactory: liveTransportFactory())
    }()

    nonisolated static func liveTransportFactory() -> TransportFactory {
        if ProcessInfo.processInfo.environment["CLICKY_MOCK"] == "1" {
            return { try MockSession(scenarioJSON: try SessionCoordinator.demoCancelScenarioJSON(),
                                     sleeper: RealSleeper()) }
        }
        return {
            guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty,
                  let url = GeminiEndpoint.webSocketURL(apiKey: key) else {
                throw GeminiClientError.transportUnavailable
            }
            return URLSessionWebSocketTransport(url: url)
        }
    }

    /// The Chunk-5 `demo-delete-note` script plus the spoken-cancel beat so mock
    /// mode exercises the confirmation gate end to end ("No, cancel that!").
    nonisolated static func demoCancelScenarioJSON() throws -> String {
        var scenario = try JSONDecoder().decode(MockSession.Scenario.self,
                                                from: Data(MockSession.demoScenarioJSON.utf8))
        if scenario.frames.indices.contains(2) {
            scenario.frames[2] = try JSONDecoder().decode([MockSession.Frame].self, from: Data(#"""
            [{"afterMs":200,"json":"{\"toolCall\":{\"functionCalls\":[{\"id\":\"demo-fc-1\",\"name\":\"execute_action\",\"args\":{\"intent\":\"Delete my project notes\",\"action\":\"delete_target\",\"target\":\"Project\"}}]}}"}]
            """#.utf8))[0]
        }
        let cancelBeat = try JSONDecoder().decode([MockSession.Frame].self, from: Data(#"""
        [{"afterMs":1500,"json":"{\"serverContent\":{\"inputTranscription\":{\"text\":\"No, cancel that!\"}}}"},
         {"afterMs":150,"json":"{\"serverContent\":{\"turnComplete\":true}}"}]
        """#.utf8))
        scenario.frames.append(contentsOf: cancelBeat)
        return String(decoding: try JSONEncoder().encode(scenario), as: UTF8.self)
    }

    func observeAppState() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .clickySessionStateChanged,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let state = note.object as? SessionState else { return }
            Task { @MainActor in
                switch state {
                case .listening: await self?.start()
                case .stopped(let reason): await self?.stop(reason: reason)
                case .idle: await self?.stop(reason: .userToggle)
                case .reconnecting: break
                }
            }
        }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        // A start generation token makes a stop() that lands during any of the
        // awaits below authoritative: the superseded start returns without
        // installing audio/kill-switch state, and the stop() has already torn
        // down whatever this start managed to install before the await.
        startGeneration &+= 1
        let generation = startGeneration
        modelTurnActive = false
        let router = ToolRouter(ledger: ledger, risk: risk, screenContext: screenContext,
                                system: system, overlay: overlay, gate: gate,
                                confirmationTimeout: confirmationTimeout)
        self.router = router
        let live = GeminiLiveClient(
            transportFactory: transportFactory,
            setupFactory: { handle in
                GeminiSetupBuilder.make(systemInstruction: SystemInstruction.text,
                                        tools: ClickyTools.declarations,
                                        resumptionHandle: handle)
            },
            toolHandler: router,
            onServerContent: { [weak self] content in Task { @MainActor in await self?.handle(content) } },
            onNotice: { [weak self] text in Task { @MainActor in self?.onNotice?(text) } },
            onMarker: { [weak self] marker in Task { @MainActor in self?.onMarker?(marker) } })
        client = live
        do {
            try await live.start()
        } catch {
            guard isCurrent(generation) else { return }
            isRunning = false
            client = nil
            self.router = nil
            onNotice?("Session could not start (\(error)).")
            return
        }
        guard isCurrent(generation) else { return }
        await warmer?.warmFrontmostWindow()
        guard isCurrent(generation) else { return }
        do {
            // Ordered bridge from the engine's serial processing queue to the client
            // actor: `onInputChunk` is synchronous, so an AsyncStream preserves the
            // 20 ms frame order without fire-and-forget Task reordering.
            let (stream, continuation) = AsyncStream<[Int16]>.makeStream()
            audioContinuation = continuation
            audioSendTask = Task { [weak live] in
                for await samples in stream {
                    guard let live else { break }
                    do { try await live.sendAudioFrame(samples) }
                    catch { /* connection state is surfaced via onNotice */ }
                }
            }
            try await audio.start { samples in
                continuation.yield(samples)
            } onSpeechOnset: { [weak self] onset in
                Task { @MainActor in
                    await self?.warmer?.speculateFrontmost()
                    await self?.stopSignal.triggerBargeIn(onset: onset)
                }
            }
            guard isCurrent(generation) else { return }
            await stopSignal.resetLatch()
            guard isCurrent(generation) else { return }
            await stopSignal.start { [weak self] reason in
                Task { @MainActor in await self?.handleStopSignal(reason) }
            }
        } catch {
            guard isCurrent(generation) else { return }
            onNotice?("Audio or kill switch failed to start (\(error)).")
            await stop(reason: .userToggle)
        }
    }

    /// True only while this start attempt is still the live session (not superseded
    /// by a stop() during an await).
    private func isCurrent(_ generation: Int) -> Bool { isRunning && generation == startGeneration }

    func stop(reason: StopReason) async {
        guard isRunning else { return }
        isRunning = false
        modelTurnActive = false
        audioContinuation?.finish()
        audioContinuation = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        await client?.stop(reason: reason)
        client = nil
        router = nil
        await audio.stop()
        await stopSignal.stop()
    }

    private func handle(_ content: GeminiServerContent) async {
        if content.interrupted == true {
            modelTurnActive = false
            await audio.stopPlaybackNow()
        }
        let chunks = content.audioBase64Chunks
        if !chunks.isEmpty {
            if !modelTurnActive {
                modelTurnActive = true
                await stopSignal.resetLatch()
                await audio.beginPlaybackTurn()
            }
            await audio.enqueueModelAudio(chunks)
        }
        if let text = content.inputTranscription?.text, !text.isEmpty {
            await ledger.recordVoiceUtterance(text, at: Date())
            await gate.submitVoiceTranscript(text)
        }
        if content.turnComplete == true {
            modelTurnActive = false
            await gate.markPromptTurnComplete()   // starts/pauses the gate timer (spec §4.4)
            await router?.beginTurn()             // replenish the per-turn budget/dedup (spec §4.4)
        }
    }

    private func handleStopSignal(_ reason: StopReason) async {
        guard isRunning else { return }
        await overlay.present(.stopped(reason: "Clicky stopped"))
        await stop(reason: reason)
        AppState.shared.transition(.stopRequested(reason))
    }
}
