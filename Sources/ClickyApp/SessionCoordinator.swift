import ClickyAudio
import ClickyCore
import ClickyGemini
import ClickyInput
import ClickyOverlay
import Foundation

/// One event on the single ordered mic → Live feed (see `start()`): a captured
/// 20 ms frame, or the one-shot readiness marker that releases the pre-handshake
/// buffer. Carrying both on one stream makes flush ordering provable — the marker
/// can only be consumed after every frame yielded before it.
private enum AudioFeedEvent: Sendable {
    case frame([Int16])
    case ready
}

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
    let killSwitch: (any KillSwitchPort)?
    let warmer: (any ScreenCacheWarming)?
    let transportFactory: TransportFactory
    let confirmationTimeout: TimeInterval
    /// Quiet-gap window for the voice-transcription buffer (FIX 2): after this
    /// long without a new fragment, a multi-fragment turn is recorded joined.
    let transcriptionQuietGap: TimeInterval

    var onNotice: ((String) -> Void)?
    var onMarker: ((GeminiMarker) -> Void)?
    private(set) var isRunning = false
    private var startGeneration = 0
    private(set) var client: GeminiLiveClient?
    private(set) var router: ToolRouter?
    private var modelTurnActive = false
    private var audioContinuation: AsyncStream<AudioFeedEvent>.Continuation?
    private var audioSendTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    /// Fragments of the current voice turn (FIX 2). Each fragment is still
    /// recorded and submitted to the gate as before; the buffer only feeds the
    /// once-per-turn joined ledger record for T10 traceability.
    private var transcriptionFragments: [String] = []
    private var transcriptionFlushTask: Task<Void, Never>?

    init(ledger: any IntentLedgerPort, risk: any RiskClassifyingPort,
         screenContext: any ScreenContextProviding, system: any SystemActionPort,
         overlay: any GhostCursorPort, gate: any ConfirmationGatingPort,
         audio: any AudioSessionPort, stopSignal: any StopSignalPort,
         killSwitch: (any KillSwitchPort)? = nil,
         warmer: (any ScreenCacheWarming)? = nil,
         transportFactory: @escaping TransportFactory,
         confirmationTimeout: TimeInterval = ToolRouter.defaultConfirmationTimeout,
         transcriptionQuietGap: TimeInterval = 1.5) {
        self.ledger = ledger; self.risk = risk; self.screenContext = screenContext
        self.system = system; self.overlay = overlay; self.gate = gate
        self.audio = audio; self.stopSignal = stopSignal; self.killSwitch = killSwitch
        self.warmer = warmer
        self.transportFactory = transportFactory; self.confirmationTimeout = confirmationTimeout
        self.transcriptionQuietGap = transcriptionQuietGap
    }

    static let shared: SessionCoordinator = {
        let synthesizer = EventSynthesizer()
        let engine = AudioStreamEngine()
        let ax = AXEngineAdapter(synthesizer: synthesizer)
        let kill = KillSwitchAdapter(playbackStop: { engine.stopPlaybackNow() })
        return SessionCoordinator(ledger: LedgerAdapter(), risk: RiskAdapter(),
                                  screenContext: ax, system: ax,
                                  overlay: OverlayAdapter(), gate: GateAdapter(),
                                  audio: AudioAdapter(engine: engine),
                                  stopSignal: kill, killSwitch: kill,
                                  warmer: ax,
                                  transportFactory: liveTransportFactory())
    }()

    nonisolated static func liveTransportFactory() -> TransportFactory {
        if ProcessInfo.processInfo.environment["CLICKY_MOCK"] == "1" {
            return { try MockSession(scenarioJSON: try SessionCoordinator.demoCancelScenarioJSON(),
                                     sleeper: RealSleeper()) }
        }
        return {
            guard let key = KeySource.geminiKey(),
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
            [{"afterMs":200,"json":"{\"toolCall\":{\"functionCalls\":[{\"id\":\"demo-fc-1\",\"name\":\"execute_action\",\"args\":{\"intent\":\"Delete my project note\",\"action\":\"delete_target\",\"target\":\"Project\"}}]}}"}]
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
        // Live vision (`look_at_screen`): the router holds the adapter and the
        // adapter holds the Live client, so the client is attached right after
        // both exist — always before `live.start()`, and therefore before any
        // tool call can run. A permission denial also surfaces a UI notice.
        let screenLooking = ScreenLookingAdapter(notice: { [weak self] text in
            Task { @MainActor in self?.onNotice?(text) }
        })
        // Web access (`web_search` / `web_fetch`): the adapter is request-scoped
        // and needs no client attach, so it is passed straight to the router.
        let webAccessing = WebAccessAdapter()
        let router = ToolRouter(ledger: ledger, risk: risk, screenContext: screenContext,
                                system: system, overlay: overlay, gate: gate,
                                killSwitch: killSwitch,
                                confirmationTimeout: confirmationTimeout,
                                screenLooking: screenLooking,
                                webAccessing: webAccessing)
        self.router = router
        // On-screen confirmation card → pending-action gate (Task T-OVERLAY). The
        // card's buttons call the overlay singleton; the gate keeps its ≥500 ms
        // arm window + TOCTOU revalidation. The closure holds `self` weakly so the
        // singleton never retains a session.
        OverlayWindowController.shared.onCardAction = { [weak self] action in
            Task { @MainActor in await self?.handleCardAction(action) }
        }
        let live = GeminiLiveClient(
            transportFactory: transportFactory,
            setupFactory: { handle in
                GeminiSetupBuilder.make(systemInstruction: SystemInstruction.sessionText,
                                        tools: ClickyTools.declarations,
                                        resumptionHandle: handle)
            },
            toolHandler: router,
            onServerContent: { [weak self] content in Task { @MainActor in await self?.handle(content) } },
            onNotice: { [weak self] text in Task { @MainActor in self?.onNotice?(text) } },
            onMarker: { [weak self] marker in Task { @MainActor in self?.onMarker?(marker) } })
        await screenLooking.attach(client: live)
        // A stop() that landed during the attach await is authoritative — return
        // without installing a stale client (the generation-token contract).
        guard isCurrent(generation) else { return }
        client = live
        // Register the local stop observer and re-arm the latch BEFORE the client can
        // process a tool call: a circuit-breaker escalation in the connect window must
        // never be dropped just because audio/kill-switch start has not finished
        // (spec §4.4). The observer is torn down on any start failure below.
        await stopSignal.resetLatch()
        guard isCurrent(generation) else { return }
        await stopSignal.start { [weak self] reason in
            Task { @MainActor in await self?.handleStopSignal(reason) }
        }
        // A stop() that landed while registering above is authoritative: return before
        // opening the mic or connecting, which would otherwise leave capture or an
        // orphaned client running with no reachable stop path.
        guard isCurrent(generation) else { return }
        // Deaf-window fix (the #1 live failure): capture starts BEFORE the Live
        // handshake, not after it. Speech during the 800–1800 ms WebSocket setup is
        // buffered by the single audio-forwarding task (bounded; oldest dropped on
        // overflow) and flushed in order the moment the session is ready.
        do {
            // Ordered bridge from the engine's serial processing queue to the client
            // actor: `onInputChunk` is synchronous, so an AsyncStream preserves the
            // 20 ms frame order without fire-and-forget Task reordering. The `.ready`
            // marker travels the SAME stream, so the pre-handshake buffer drains
            // before any later frame is sent — one producer order, one consumer,
            // ordering provable without locks.
            let (stream, continuation) = AsyncStream<AudioFeedEvent>.makeStream()
            audioContinuation = continuation
            audioSendTask = Task { [weak live] in
                var buffer = AudioFrameBuffer()
                var isReady = false
                for await event in stream {
                    guard let live else { break }
                    switch event {
                    case .frame(let samples):
                        if isReady {
                            do { try await live.sendAudioFrame(samples) }
                            catch { /* connection state is surfaced via onNotice */ }
                        } else {
                            buffer.append(samples)
                        }
                    case .ready:
                        isReady = true
                        for samples in buffer.drain() {
                            do { try await live.sendAudioFrame(samples) }
                            catch { /* connection state is surfaced via onNotice */ }
                        }
                    }
                }
            }
            try await audio.start { samples in
                continuation.yield(.frame(samples))
            } onSpeechOnset: { [weak self] onset in
                Task { @MainActor in
                    await self?.warmer?.speculateFrontmost()
                    await self?.stopSignal.triggerBargeIn(onset: onset)
                }
            }
        } catch {
            guard isCurrent(generation) else { return }
            onNotice?("Audio or kill switch failed to start (\(error)).")
            await stop(reason: .userToggle)
            return
        }
        guard isCurrent(generation) else { return }
        do {
            try await live.start()
        } catch {
            guard isCurrent(generation) else { return }
            isRunning = false
            client = nil
            self.router = nil
            // Capture is already live (it starts before the handshake): stop it and
            // discard anything buffered during the failed handshake — the failure
            // path must not leave the mic hot.
            audioContinuation?.finish()
            audioContinuation = nil
            audioSendTask?.cancel()
            audioSendTask = nil
            await audio.stop()
            await stopSignal.stop()
            postModelActivity(.hidden)
            onNotice?("Session could not start (\(error)).")
            return
        }
        guard isCurrent(generation) else { return }
        // Handshake done: release the buffered frames; streaming continues live.
        audioContinuation?.yield(.ready)
        postModelActivity(.listening)
        guard isCurrent(generation) else { return }
        await warmer?.warmFrontmostWindow()
    }

    /// True only while this start attempt is still the live session (not superseded
    /// by a stop() during an await).
    private func isCurrent(_ generation: Int) -> Bool { isRunning && generation == startGeneration }

    func stop(reason: StopReason) async {
        guard isRunning else { return }
        isRunning = false
        postModelActivity(.hidden)
        let generation = startGeneration
        modelTurnActive = false
        transcriptionFlushTask?.cancel()
        transcriptionFlushTask = nil
        transcriptionFragments.removeAll()
        audioContinuation?.finish()
        audioContinuation = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        // Detach this session's client/router synchronously and keep the reference, so
        // an older stop that is still awaiting teardown can never clobber a newer
        // start's state. The generation guards protect the remaining awaits.
        let doomed = client
        client = nil
        router = nil
        await doomed?.stop(reason: reason)
        guard generation == startGeneration else { return }   // a newer start owns the state now
        await audio.stop()
        guard generation == startGeneration else { return }
        await stopSignal.stop()
    }

    /// The text-command fallback (spec §2: voice-first, not voice-only). Typed
    /// input is a local user channel exactly like speech (errata C3): it is
    /// recorded in the intent ledger for T10 provenance, offered to the
    /// confirmation gate (so typed "haan"/"confirm" confirms a pending action),
    /// then sent to the Live model as a text turn.
    func submitTypedCommand(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isRunning, let client else {
            onNotice?("Typed command could not be sent (no live session is running).")
            return
        }
        // Local channels first, so a typed confirmation still lands even if the
        // socket hiccups on the model send below. `recordVoiceUtterance` is the
        // port's only recording entry point; `authorize` treats ledger sources
        // alike, so the typed intent is traceable exactly like a spoken one.
        await ledger.recordVoiceUtterance(trimmed, at: Date())
        await gate.submitVoiceTranscript(trimmed)
        let generation = startGeneration
        do {
            try await client.sendTextTurn(trimmed)
        } catch {
            // A stop that landed while sending is not a failure worth surfacing.
            guard isCurrent(generation) else { return }
            onNotice?("Typed command could not be sent (\(error)).")
        }
    }

    private func handle(_ content: GeminiServerContent) async {
        if content.interrupted == true {
            modelTurnActive = false
            postModelActivity(.listening)
            await audio.stopPlaybackNow()
        }
        let chunks = content.audioBase64Chunks
        if !chunks.isEmpty {
            if !modelTurnActive {
                modelTurnActive = true
                postModelActivity(.speaking)
                await stopSignal.resetLatch()
                await audio.beginPlaybackTurn()
            }
            await audio.enqueueModelAudio(chunks)
        }
        if let text = content.inputTranscription?.text, !text.isEmpty {
            postModelActivity(.thinking)
            // Buffer first, synchronously: a later turnComplete/quiet-gap flush
            // must never run before this fragment is in the buffer (handle()
            // tasks interleave at the awaits below).
            bufferTranscriptionFragment(text)
            await ledger.recordVoiceUtterance(text, at: Date())
            await gate.submitVoiceTranscript(text)
        }
        if content.turnComplete == true {
            transcriptionFlushTask?.cancel()
            transcriptionFlushTask = nil
            await flushTranscriptionFragments()
            modelTurnActive = false
            postModelActivity(.listening)
            await gate.markPromptTurnComplete()   // starts/pauses the gate timer (spec §4.4)
            await router?.beginTurn()             // replenish the per-turn budget/dedup (spec §4.4)
        }
    }

    /// FIX 2 (T10 traceability): the Live API streams `inputTranscription` in
    /// fragments, and the model's `intent` paraphrases the whole utterance —
    /// per-fragment records alone often fail the ledger's anchor match (live
    /// logs: legitimate "Open a new tab" / "Switch to browser" were refused).
    /// Buffer the fragments and start a quiet-gap debounce; the joined record is
    /// written at `turnComplete` or when the gap expires, at most once per turn.
    private func bufferTranscriptionFragment(_ text: String) {
        transcriptionFragments.append(text)
        transcriptionFlushTask?.cancel()
        transcriptionFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let seconds = self.transcriptionQuietGap.isFinite
                ? min(max(0, self.transcriptionQuietGap), 86_400) : 0
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.flushTranscriptionFragments()
        }
    }

    /// Records the joined utterance once for a multi-fragment turn, in addition
    /// to the per-fragment records already written. Single-fragment turns are
    /// left exactly as before (the per-fragment record is the record).
    private func flushTranscriptionFragments() async {
        transcriptionFlushTask = nil
        let fragments = transcriptionFragments
        transcriptionFragments.removeAll()
        guard fragments.count > 1 else { return }
        await ledger.recordVoiceUtterance(fragments.joined(separator: " "), at: Date())
    }

    /// Ambient companion presence (Task T-OVERLAY): the overlay observes
    /// `.clickyModelActivityChanged` on the main queue, so posting from the main
    /// actor is cheap and ordered with the session transitions above.
    private func postModelActivity(_ activity: CompanionActivity) {
        NotificationCenter.default.post(name: .clickyModelActivityChanged, object: activity)
    }

    /// On-screen confirmation card decision (Task T-OVERLAY): the card buttons
    /// call `OverlayWindowController.shared.onCardAction`, wired to this method in
    /// `start()`. The gate owns the ≥500 ms arm window + TOCTOU revalidation; no
    /// extra ledger record is needed because the pending action was already
    /// authorized by a traceable voice intent before it armed.
    private func handleCardAction(_ action: OverlayCardAction) async {
        await gate.submitCardDecision(confirmed: action == .confirm)
    }

    private func handleStopSignal(_ reason: StopReason) async {
        guard isRunning else { return }
        await overlay.present(.stopped(reason: "Clicky stopped"))
        await stop(reason: reason)
        AppState.shared.transition(.stopRequested(reason))
    }
}
