import AppKit
import ApplicationServices
import ClickyAccessibility
import ClickyAudio
import ClickyCore
import ClickyGemini
import ClickyInput
import ClickyOverlay
import ClickySafety
import Foundation

// Chunk-13 adapter layer. This is the ONLY file that names the concrete Chunk 6–11
// APIs; it wires them into the Chunk 12 port protocols that `ToolRouter` consumes.
//
//   ClickyAccessibility:
//     AXTreeCrawler.shared.snapshot(focusedWindowOf:) -> [ElementSnapshot] (flat,
//       focused window first); ElementSnapshot.key (CacheKey.role/subrole/title/
//       description), .frame (global CG, y-down), .isEnabled, .actions
//     AXHotCache.shared.activate(pid:) / speculate() / crawlNow() /
//       lookup(_ query: ElementQuery) -> ScoredElement.snapshot
//   ClickyInput:
//     EventSynthesizer.click(element:) / typeText(_:into:preferPaste:) /
//       scroll(_:on:) / pressKey(_:on:) / releaseHeldInput()
//     SecureInputGuard.evaluate(element:) -> SecureInputDecision
//     SystemEventPoster.postKeyChord(keyCode:flags:) (the ⌘⌫ Tier-3 delete path)
//   ClickySafety:
//     IntentLedger.record(_:source:) / authorize(_:)
//     RiskGatekeeper.classify(_:) ; RiskContext / RiskAction ; RiskTier
//     PendingActionGate.present/promptTurnComplete/userSpoke/awaitArmAndRevalidate
//   ClickyAudio: AudioStreamEngine (onInputChunk / onVADEvent / start / stop /
//     beginPlaybackTurn / enqueuePlaybackPCM / stopPlaybackNow)
//   ClickyOverlay: OverlayWindowController.shared.presentMoving/presentReview/
//     presentConfirmation/presentStopped

/// Chunk-13 seam for pre-warming the Chunk 6 AX hot cache. Deliberately not part
/// of `ToolRouter`'s ports (those are frozen); the app injects the concrete
/// adapter and tests may omit it.
protocol ScreenCacheWarming: Sendable {
    /// Activate the observer for the frontmost app and warm the cache (session start).
    func warmFrontmostWindow() async
    /// Speculative refresh on voice onset so the `toolCall` lands on a warm cache.
    func speculateFrontmost() async
}

/// The Chunk 6 accessibility surface behind `ScreenContextProviding` and
/// `SystemActionPort`. AX work stays on this actor, never `@MainActor`.
actor AXEngineAdapter: ScreenContextProviding, SystemActionPort, ScreenCacheWarming {
    /// ANSI Delete (Backspace); ⌘⌫ is the approved Tier-3 `delete_target` mechanism.
    private static let deleteKeyCode: CGKeyCode = 51

    private let crawler: AXTreeCrawler
    private let cache: AXHotCache
    private let synthesizer: EventSynthesizer
    private var lastWindowTitle = ""

    init(crawler: AXTreeCrawler = .shared, cache: AXHotCache = .shared,
         synthesizer: EventSynthesizer = EventSynthesizer()) {
        self.crawler = crawler
        self.cache = cache
        self.synthesizer = synthesizer
    }

    // MARK: ScreenContextProviding

    func captureContext(reason: String, maxNodes: Int) async -> ScreenContext {
        guard let pid = Self.frontmostPID() else {
            return ScreenContext(applicationName: "", windowTitle: "", elements: [])
        }
        let tree = await crawler.snapshot(focusedWindowOf: pid)
        // Decision (a): the crawled focused window snapshot (first, focused window
        // first) supplies `windowTitle` from its `key.title`.
        if let window = tree.first { lastWindowTitle = window.key.title }
        let elements = tree.prefix(max(0, maxNodes)).map { snapshot in
            ScreenContextElement(role: snapshot.key.role,
                                 subrole: snapshot.key.subrole.isEmpty ? nil : snapshot.key.subrole,
                                 title: snapshot.key.title,
                                 elementDescription: snapshot.key.description.isEmpty ? nil : snapshot.key.description,
                                 enabled: snapshot.isEnabled,
                                 actions: snapshot.actions)
        }
        return ScreenContext(applicationName: Self.applicationName(for: pid),
                             windowTitle: lastWindowTitle, elements: Array(elements))
    }

    // MARK: SystemActionPort

    func resolve(title: String?, kind: ClickyActionKind) async -> ResolvedTarget? {
        guard let title, !title.isEmpty, let pid = Self.frontmostPID() else { return nil }
        await cache.activate(pid: pid)
        let query = ElementQuery(text: title)
        if let match = await cache.lookup(query) { return await makeTarget(match.snapshot, pid: pid) }
        await cache.crawlNow()
        guard let match = await cache.lookup(query) else { return nil }
        return await makeTarget(match.snapshot, pid: pid)
    }

    func perform(_ action: ResolvedAction) async -> ActionOutcome {
        switch action.kind {
        case .openURL:
            guard let text = action.text, let url = URL(string: text) else { return .failed(reason: "invalid url") }
            return NSWorkspace.shared.open(url)
                ? .performed(detail: "opened \(url.host ?? text)") : .failed(reason: "open failed")

        case .switchApp:
            guard let name = action.text else { return .failed(reason: "missing app name") }
            guard let activated = await Self.activate(name: name) else { return .failed(reason: "app not found") }
            return .performed(detail: "switched to \(activated)")

        case .click:
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            switch await synthesizer.click(element: element.element) {
            case .axPressed: return .performed(detail: "pressed")
            case .clickFallback: return .performed(detail: "clicked fallback")
            case .noTargetPoint: return .failed(reason: "could not resolve a click point")
            }

        case .deleteTarget:
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            let secure = SecureInputGuard.evaluate(element: element.element)
            guard secure.isAllowed else { return .refused(reason: "secure input: \(secure.rule.rawValue)") }
            // Approved Tier-3 design: focus the resolved target, then ⌘⌫ (the item
            // moves to Recently Deleted; recoverable). No fileURL extraction.
            if case .noTargetPoint = await synthesizer.click(element: element.element) {
                return .failed(reason: "could not focus the target")
            }
            SystemEventPoster().postKeyChord(keyCode: Self.deleteKeyCode, flags: .maskCommand)
            return .performed(detail: "moved to Recently Deleted")

        case .typeText, .paste:
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            let secure = SecureInputGuard.evaluate(element: element.element)
            guard secure.isAllowed else { return .refused(reason: "secure input: \(secure.rule.rawValue)") }
            let outcome = await synthesizer.typeText(action.text ?? "", into: element.element,
                                                     preferPaste: action.kind == .paste)
            switch outcome {
            case .directVerified: return .performed(detail: "typed and verified")
            case .pasteboardVerified: return .performed(detail: "pasted and verified")
            case .blocked(let rule): return .refused(reason: "secure input rule: \(rule.rawValue)")
            case .unverified(let reason): return .failed(reason: reason)
            }

        case .scroll:
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            return await synthesizer.scroll(action.text ?? "down", on: element.element)
                ? .performed(detail: "scrolled") : .failed(reason: "scroll failed")

        case .keyPress:
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            return await synthesizer.pressKey(action.text ?? "", on: element.element)
                ? .performed(detail: "key pressed") : .failed(reason: "key press failed")
        }
    }

    // MARK: ScreenCacheWarming

    func warmFrontmostWindow() async {
        guard let pid = Self.frontmostPID() else { return }
        await cache.activate(pid: pid)
        await cache.crawlNow()
        if let window = await crawler.snapshot(focusedWindowOf: pid).first { lastWindowTitle = window.key.title }
    }

    func speculateFrontmost() async {
        guard let pid = Self.frontmostPID() else { return }
        await cache.activate(pid: pid)
        await cache.speculate()
    }

    // MARK: Helpers

    private func resolveElement(_ target: ResolvedTarget?) async -> ElementSnapshot? {
        guard let target, let pid = Self.frontmostPID() else { return nil }
        await cache.activate(pid: pid)
        let query = ElementQuery(text: target.title, role: target.role)
        if let match = await cache.lookup(query) { return match.snapshot }
        await cache.crawlNow()
        return await cache.lookup(query)?.snapshot
    }

    private func makeTarget(_ snapshot: ElementSnapshot, pid: pid_t) async -> ResolvedTarget {
        ResolvedTarget(applicationName: Self.applicationName(for: pid),
                       role: snapshot.key.role,
                       subrole: snapshot.key.subrole.isEmpty ? nil : snapshot.key.subrole,
                       title: snapshot.key.title,
                       windowTitle: await windowTitle(for: pid),
                       cgFrame: snapshot.frame)
    }

    private func windowTitle(for pid: pid_t) async -> String {
        if !lastWindowTitle.isEmpty { return lastWindowTitle }
        lastWindowTitle = await crawler.snapshot(focusedWindowOf: pid).first?.key.title ?? ""
        return lastWindowTitle
    }

    private static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Decision (a): `applicationName` is the `NSRunningApplication.localizedName`
    /// for the target pid — no new AX attributes.
    private static func applicationName(for pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    /// Tier-2 `switch_app`: activate an already-running regular app on a spoken-name
    /// match, else open `<name>.app` from the three standard folders. No deprecated
    /// `launchApplication`; no path ever comes from speech.
    private static func activate(name: String) async -> String? {
        let normalized = name.lowercased()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let match = running.first { $0.localizedName?.lowercased() == normalized }
            ?? running.first { $0.bundleIdentifier?.lowercased().hasSuffix(normalized) == true }
            ?? running.first { $0.localizedName?.lowercased().hasPrefix(normalized) == true }
        if let match {
            match.activate(from: .current, options: [.activateAllWindows])
            return match.localizedName ?? name
        }
        let folders = ["/Applications", "/System/Applications",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let target = "\(normalized).app"
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder),
                  let entry = entries.first(where: { $0.lowercased() == target }) else { continue }
            let url = URL(fileURLWithPath: folder).appendingPathComponent(entry)
            if await openApplication(url) { return FileManager.default.displayName(atPath: url.path) }
        }
        return nil
    }

    private static func openApplication(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url,
                                               configuration: NSWorkspace.OpenConfiguration()) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }
}

// MARK: - Safety adapters

actor LedgerAdapter: IntentLedgerPort {
    private let ledger = IntentLedger()

    func recordVoiceUtterance(_ text: String, at date: Date) async {
        await ledger.record(text, source: .voice)
    }

    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool {
        let call = IntentLedger.ToolCallIntent(toolName: "execute_action", anchors: [intent])
        switch await ledger.authorize(call) {
        case .authorized: return true
        case .refused: return false
        }
    }
}

struct RiskAdapter: RiskClassifyingPort {
    func classify(kind: ClickyActionKind, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier {
        let action: RiskAction
        switch kind {
        case .click: action = .click
        case .typeText: action = .typeText
        case .paste: action = .clipboardWrite
        case .scroll: action = .navigate
        case .openURL: action = .openURL(parameters: false)
        case .switchApp: action = .navigate
        case .deleteTarget: action = .trashFile
        case .keyPress: action = .click
        }
        let effectiveAction = hasAmount ? .financial : action
        let context = RiskContext(action: effectiveAction, targetSubrole: targetSubrole, targetTitle: targetTitle)
        return RiskGatekeeper.classify(context).tier
    }
}

actor GateAdapter: ConfirmationGatingPort {
    private let gate: PendingActionGate
    private var pendingContinuation: CheckedContinuation<ConfirmationDecision, Never>?
    private var currentActionID: UUID?
    /// The one live expiry timer for the current `pendingContinuation`. Cancelled and
    /// replaced on every arm (and on resolution) so a superseding arm can never leave
    /// a pending continuation without a timeout.
    private var timeoutTask: Task<Void, Never>?

    init(gate: PendingActionGate = PendingActionGate()) {
        self.gate = gate
    }

    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision {
        let expectedAmount = request.amount.flatMap { Decimal(string: $0) }
        let anchors = request.summary.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty } + [request.summary]
        let action = PendingActionGate.PendingAction(id: request.actionID, description: request.summary,
                                                     tier: request.tier, anchors: anchors,
                                                     expectedAmount: expectedAmount)
        await gate.present(action)
        currentActionID = request.actionID
        return await withCheckedContinuation { continuation in
            if let old = self.pendingContinuation {
                self.pendingContinuation = continuation
                old.resume(returning: .cancelled(reason: "superseded"))
            } else {
                self.pendingContinuation = continuation
            }
            // Every arm owns exactly one live timeout: the superseded continuation was
            // just resumed, so cancel its timer and start one for the new continuation.
            self.timeoutTask?.cancel()
            let timeoutSeconds = max(request.timeoutSeconds, PendingActionGate.minimumTimeout)
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((timeoutSeconds + 2) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.handleTimeout(for: request.actionID)
            }
        }
    }

    func submitVoiceTranscript(_ text: String) async {
        let outcome = await gate.userSpoke(text)
        switch outcome {
        case .accepted:
            if let id = currentActionID {
                let armOutcome = await gate.awaitArmAndRevalidate(id: id) { _ in true }
                switch armOutcome {
                case .execute: resume(with: .confirmed(source: .voiceTranscript))
                case .abort(let reason): resume(with: .cancelled(reason: reason.rawValue))
                }
            } else {
                resume(with: .confirmed(source: .voiceTranscript))
            }
        case .cancelled(let reason):
            resume(with: .cancelled(reason: reason.rawValue))
        case .ignored:
            break
        }
    }

    func submitModelDecision(confirmed: Bool, echo: String) async {
        // No-op: confirmation gate receives ONLY local inputs per errata C3.
    }

    func markPromptTurnComplete() async {
        await gate.promptTurnComplete()
    }

    private func handleTimeout(for actionID: UUID) {
        guard currentActionID == actionID else { return }
        resume(with: .expired)
    }

    private func resume(with decision: ConfirmationDecision) {
        if let cont = pendingContinuation {
            pendingContinuation = nil
            currentActionID = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            cont.resume(returning: decision)
        }
    }
}

// MARK: - Overlay adapter

actor OverlayAdapter: GhostCursorPort {
    func present(_ presentation: GhostCursorPresentation) async {
        await MainActor.run {
            switch presentation {
            case .moving(let point): OverlayWindowController.shared.presentMoving(at: point)
            case .review(let rect, let label): OverlayWindowController.shared.presentReview(rect: rect, label: label)
            case .confirm(let rect, let label): OverlayWindowController.shared.presentConfirmation(rect: rect, label: label)
            case .stopped(let reason): OverlayWindowController.shared.presentStopped(reason: reason)
            }
        }
    }
}

// MARK: - Audio adapter

/// Chunk-13 wrapper around the Chunk 10 `AudioStreamEngine`. The engine's `start()`
/// is synchronous and takes no frame callback, so input is delivered through
/// `onInputChunk`; VAD onsets flow back through `onVADEvent`. Model audio (24 kHz
/// base64 PCM) is enqueued through the same VPIO graph.
actor AudioAdapter: AudioSessionPort {
    private let engine: AudioStreamEngine

    init(engine: AudioStreamEngine = AudioStreamEngine()) {
        self.engine = engine
    }

    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {
        engine.onInputChunk = { chunk in onFrame(chunk.samples) }
        engine.onVADEvent = { event, captureStart in
            if case .speechOnset = event { onSpeechOnset(captureStart) }
        }
        try engine.start()
    }

    func stop() async { engine.stop() }

    func beginPlaybackTurn() async { engine.beginPlaybackTurn() }

    func enqueueModelAudio(_ base64Chunks: [String]) async {
        for chunk in base64Chunks {
            guard let data = Data(base64Encoded: chunk) else { continue }
            engine.enqueuePlaybackPCM(data, sampleRate: 24_000)
        }
    }

    func stopPlaybackNow() async { engine.stopPlaybackNow() }
}

// MARK: - Kill-switch adapter

/// The session's local stop seam. This manager is NOT hotkey-registered: the app's
/// single ⌘⇧X registration lives in `AppDelegate.installHotKeys()`. `start(onStop:)`
/// observes `KillSwitchManager.notificationName` and delivers a full session stop
/// for the ⌘⇧X / menu sources only; voice onset is a barge-in (playback stop) and
/// never ends the session. The registered manager's own latch is re-armed by the app
/// at each `.listening` transition (see `AppDelegate`), because this actor cannot see
/// that instance.
actor KillSwitchAdapter: StopSignalPort {
    private let manager: KillSwitchManager
    private var observer: NSObjectProtocol?
    private var onStop: (@Sendable (StopReason) -> Void)?

    init(playbackStop: @escaping @Sendable () -> Void) {
        self.manager = KillSwitchManager(hooks: KillSwitchManager.Hooks(
            stopPlayback: playbackStop,
            releaseSyntheticInput: { KillSwitchManager.releaseSyntheticInputNow() },
            presentBanner: { _ in },
            stopSession: {}))
    }

    func start(onStop: @escaping @Sendable (StopReason) -> Void) async {
        self.onStop = onStop
        manager.reset()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: KillSwitchManager.notificationName,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let source = note.object as? KillSwitchManager.Source,
                  source == .hotKey || source == .menuBar else { return }
            Task { await self?.deliverStop() }
        }
    }

    func stop() async {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        onStop = nil
    }

    /// Re-arms this session's own (VAD barge-in) latch. The registered ⌘⇧X
    /// manager's latch is reset separately by the app at `.listening`.
    func resetLatch() async { manager.reset() }

    func triggerBargeIn(onset: ContinuousClock.Instant) async {
        manager.triggerBargeIn(source: .voiceOnset, onset: onset)
    }

    private func deliverStop() {
        onStop?(.killSwitch)
    }
}
