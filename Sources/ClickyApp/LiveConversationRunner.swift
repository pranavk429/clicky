import AppKit
import Carbon.HIToolbox
import ClickyAudio
import ClickyCore
import ClickyGemini
import ClickyInput
import ClickyOverlay
import CoreGraphics
import Foundation

/// The Chunk 5.5 Wave-1 live English conversation slice: microphone → Live API →
/// streaming playback, driven through the real Ghost Cursor overlay with a local
/// Esc stop. Device- and network-bound; behavior is verified by the Task 5.5.4
/// manual OS checks, not by unit tests (there is no ClickyApp test target).
@MainActor
final class LiveConversationRunner {
    let overlay = GhostCursorController()
    let gate = DemoClickGate()

    private var client: GeminiLiveClient?
    private var mic: MicrophoneCapture?
    private var player: StreamingAudioPlayer?
    private var hotKey: EscapeHotKey?
    private var audioTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<[Int16]>.Continuation?
    private var cleanupTask: Task<Void, Never>?
    private var running = false
    private var lastAudioStreamEndAt: ContinuousClock.Instant?

    /// Menu insurance; barge-in disabled by design in this mode — Esc still stops.
    var halfDuplex = false

    nonisolated static let systemInstruction = "You are Clicky, a live voice copilot inside a menu-bar app on this Mac. English only in this build. Speak like a quick, warm conversation partner: one or two short spoken sentences per reply, never a monologue. Actions available in this build: switch_app (open or switch to an app), type_text (type text into the frontmost app after activating it), click_demo_button (a real click on Clicky's own on-screen demo panel, after the user confirms it). Use a tool when the user asks for an action, and report the real outcome — the local computer confirms what happened, so never claim an action unless its tool result came back. If you cannot do something (other languages, screen reading, payments, files), say plainly that this build cannot do it yet. The user may interrupt you at any moment; that is expected — stop and listen."

    nonisolated static let tools: [GeminiTool] = [
        GeminiTool(functionDeclarations: [
            GeminiFunctionDeclaration(
                name: "switch_app",
                description: "Open or switch to an application on this Mac. Use the app's common short name.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app": .object([
                            "type": .string("string"),
                            "description": .string("App name, for example Safari, Notes, Calculator")
                        ])
                    ]),
                    "required": .array([.string("app")])
                ])),
            GeminiFunctionDeclaration(
                name: "type_text",
                description: "Type text into the frontmost app using synthetic keystrokes. Refused while secure input is on.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("The exact text to type")
                        ]),
                        "app": .object([
                            "type": .string("string"),
                            "description": .string("Optional app to activate first")
                        ])
                    ]),
                    "required": .array([.string("text")])
                ])),
            GeminiFunctionDeclaration(
                name: "click_demo_button",
                description: "Click Clicky's own on-screen demo panel after the user confirms with the keyboard.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ]))
        ])
    ]

    func start() async {
        guard !running else { return }

        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !apiKey.isEmpty else {
            overlay.showOverlay()
            overlay.setStatus("GEMINI_API_KEY is not set — launch from a shell that sources ~/.clicky-gemini-key")
            return
        }

        guard let url = GeminiEndpoint.webSocketURL(apiKey: apiKey) else {
            overlay.showOverlay()
            overlay.setStatus("Could not build the Live endpoint URL — stopped")
            return
        }

        guard let player = try? StreamingAudioPlayer() else {
            overlay.showOverlay()
            overlay.setStatus("Audio output unavailable — check System Settings › Sound")
            return
        }

        running = true
        self.player = player
        overlay.hideOverlay()   // clear a stale stopped banner from a quick re-run
        overlay.showOverlay()
        gate.showPanel()
        overlay.setStatus("Connecting — live English slice")

        let mic = MicrophoneCapture()
        self.mic = mic

        player.onDrained = { [weak self] in
            self?.overlay.setStatus("Listening")
        }

        let (frames, continuation) = AsyncStream<[Int16]>.makeStream()
        audioContinuation = continuation
        mic.onFrame = { frame in continuation.yield(frame) }

        audioTask = Task { [weak self] in
            for await frame in frames {
                guard let self else { return }
                if self.halfDuplex && self.player?.isPlaying == true { continue }
                try? await self.client?.sendAudioFrame(frame)
            }
        }

        let client = GeminiLiveClient(
            transportFactory: { URLSessionWebSocketTransport(url: url) },
            setupFactory: { handle in
                GeminiSetupBuilder.make(systemInstruction: Self.systemInstruction,
                                        tools: Self.tools,
                                        resumptionHandle: handle)
            },
            toolHandler: LiveToolHandler(overlay: overlay, gate: gate),
            onServerContent: { [weak self] content in
                Task { @MainActor in self?.handleServerContent(content) }
            },
            onNotice: { [weak self] note in
                Task { @MainActor in self?.overlay.setStatus(note) }
            },
            onMarker: { [weak self] marker in
                Task { @MainActor in self?.handleMarker(marker) }
            })
        self.client = client

        let hotKey = EscapeHotKey { [weak self] in
            Task { @MainActor in await self?.stop(reason: .killSwitch) }
        }
        hotKey.install(GetApplicationEventTarget())
        self.hotKey = hotKey

        do {
            try mic.start()
            try player.start()
        } catch {
            overlay.setStatus("Microphone or audio unavailable — allow Clicky in System Settings › Privacy & Security › Microphone")
            await stop(reason: .networkFailure)
            return
        }

        do {
            try await client.start()
            guard running else { return }
            overlay.setStatus("Live — say hello")
        } catch {
            guard running else { return }
            overlay.setStatus("Could not connect — stopped")
            await stop(reason: .networkFailure)
        }
    }

    /// Idempotent: the first caller wins, later callers (Esc, menu, failure) no-op.
    func stop(reason: StopReason) async {
        guard running else { return }
        running = false
        hotKey?.uninstall()
        audioContinuation?.finish()
        audioTask?.cancel()
        mic?.stop()
        player?.stopAll()
        gate.cancelPending()
        gate.hidePanel()
        if let client {
            await client.stop(reason: reason)
        }
        hotKey = nil
        audioContinuation = nil
        audioTask = nil
        mic = nil
        player = nil
        client = nil
        overlay.dismissConfirmation()
        overlay.showStopped(reason == .killSwitch ? "STOPPED — local stop (no network)" : "Session ended")
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.overlay.hideOverlay()
        }
    }

    // MARK: Server callbacks

    private func handleServerContent(_ content: GeminiServerContent) {
        if content.interrupted == true {
            player?.stopAll()
            overlay.setStatus("Interrupted — listening")
        }
        if !content.audioBase64Chunks.isEmpty {
            player?.enqueue(base64Chunks: content.audioBase64Chunks)
            overlay.setStatus("Speaking")
        }
    }

    private func handleMarker(_ marker: GeminiMarker) {
        switch marker {
        case .audioStreamEndSent:
            lastAudioStreamEndAt = .now
        case .firstAudioFrameReceived:
            if let start = lastAudioStreamEndAt {
                let components = start.duration(to: .now).components
                let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
                overlay.setStatus(Self.latencyChip(seconds: seconds))
            }
            lastAudioStreamEndAt = nil
        case .interruptedReceived:
            player?.stopAll()
        case .toolCallDropped:
            overlay.setStatus("Action dropped — nothing ran")
        case .toolCallReceived, .toolResponseSent:
            break
        }
    }

    /// Measured T3 → T4 for the last voice turn — one leg only, labeled for what it
    /// is (claims discipline: no end-to-end claim until Chunk 14's meter).
    static func latencyChip(seconds: Double) -> String {
        String(format: "last reply started in %.2f s — voice-turn leg only; full meter ships in Chunk 14 (not an end-to-end claim)", seconds)
    }
}

/// Executes this build's single Tier-2 action (`switch_app`). It never opens a
/// path from speech and never leaves the three allowed application folders.
private struct LiveToolHandler: GeminiToolHandling {
    let overlay: GhostCursorController
    let gate: DemoClickGate

    func execute(_ call: GeminiToolCall.FunctionCall) async throws -> GeminiToolHandlerResult {
        switch call.name {
        case "switch_app":
            return await switchApp(call)
        case "type_text":
            return await Self.typeText(call, overlay: overlay)
        case "click_demo_button":
            return await Self.clickDemoButton(overlay: overlay, gate: gate)
        default:
            return GeminiToolHandlerResult(
                payload: .object(["status": .string("error"),
                                  "detail": .string("unknown tool \(call.name)")]),
                scheduling: .interrupted)
        }
    }

    private func switchApp(_ call: GeminiToolCall.FunctionCall) async -> GeminiToolHandlerResult {
        guard case .string(let name)? = call.args?["app"], !name.isEmpty else {
            return GeminiToolHandlerResult(
                payload: .object(["status": .string("error"),
                                  "detail": .string("switch_app needs an app name")]),
                scheduling: .interrupted)
        }
        await overlay.setIntent("Switch to \(name)")
        if let activated = await AppActivator.resolveAndActivate(name: name) {
            await overlay.flashAction("Switched to \(activated)")
            return GeminiToolHandlerResult(
                payload: .object(["status": .string("activated"), "app": .string(activated)]),
                scheduling: .whenIdle)
        }
        await overlay.setIntent(nil)
        return GeminiToolHandlerResult(
            payload: .object(["status": .string("error"),
                              "detail": .string("no standard app named \(name)")]),
            scheduling: .interrupted)
    }

    private static func typeText(_ call: GeminiToolCall.FunctionCall,
                                 overlay: GhostCursorController) async -> GeminiToolHandlerResult {
        guard case .string(let text)? = call.args?["text"], !text.isEmpty else { return error(detail: "missing text") }
        if case .string(let app)? = call.args?["app"], !app.isEmpty {
            let activated = await AppActivator.resolveAndActivate(name: app)
            guard activated != nil else { return error(detail: "no standard app named \(app)") }
        }
        guard !IsSecureEventInputEnabled() else {
            await overlay.setIntent("Refused — secure input is on")
            return GeminiToolHandlerResult(payload: .object(["status": .string("refused"),
                                                              "detail": .string("secure input is enabled")]),
                                           scheduling: .interrupted)
        }
        await overlay.setIntent("Typing \(text.count) characters")
        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in UnicodeChunker.chunk(text) {           // ≤20 UTF-16 units, grapheme-safe
            guard !IsSecureEventInputEnabled() else {
                await overlay.setIntent(nil)
                return error(detail: "secure input turned on mid-typing — stopped")
            }
            let units = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(12))
        }
        await overlay.setIntent(nil)
        await overlay.flashAction("Typed \(text.count) characters")
        return GeminiToolHandlerResult(payload: .object(["status": .string("typed")]), scheduling: .whenIdle)
    }

    private static func clickDemoButton(overlay: GhostCursorController,
                                        gate: DemoClickGate) async -> GeminiToolHandlerResult {
        await MainActor.run { gate.beginGate() }
        let point = await MainActor.run { gate.buttonScreenCenter() }
        await overlay.setIntent("Click: Clicky's own demo panel")
        await overlay.moveCursor(to: point, duration: 0.8)
        await overlay.showConfirmation("Press ⏎ to confirm — Esc stops the session")
        let confirmed = await gate.requestConfirmation()
        await overlay.dismissConfirmation()
        guard confirmed else {
            await overlay.setIntent(nil)
            await overlay.flashAction("Click cancelled — nothing was clicked")
            return GeminiToolHandlerResult(payload: .object(["status": .string("cancelled")]), scheduling: .interrupted)
        }
        _ = await MainActor.run { gate.performRealClick(at: point) }
        try? await Task.sleep(for: .milliseconds(200))
        let landed = await MainActor.run { gate.didFire }
        await overlay.setIntent(nil)
        await overlay.flashAction(landed ? "Real click landed on Clicky's own panel"
                                         : "Click not confirmed — claiming nothing")
        return GeminiToolHandlerResult(
            payload: .object(["status": .string(landed ? "clicked" : "unconfirmed"),
                              "target": .string("clicky_demo_panel")]),
            scheduling: .whenIdle)
    }

    /// Shared error result for the tool handlers in this file.
    private static func error(detail: String) -> GeminiToolHandlerResult {
        GeminiToolHandlerResult(payload: .object(["status": .string("error"),
                                                  "detail": .string(detail)]),
                                scheduling: .interrupted)
    }
}

/// Tier-2 activation rules: switch an already-running regular app if the spoken
/// name matches, otherwise open `<name>.app` from the three standard folders only.
/// Never destructive, never a path from speech.
@MainActor
private enum AppActivator {
    static func resolveAndActivate(name: String) async -> String? {
        let normalized = name.lowercased()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        let match = running.first { $0.localizedName?.lowercased() == normalized }
            ?? running.first { $0.bundleIdentifier?.lowercased().hasSuffix(normalized) == true }
            ?? running.first { $0.localizedName?.lowercased().hasPrefix(normalized) == true }
        if let match {
            match.activate(from: .current, options: [.activateAllWindows])
            return match.localizedName ?? name
        }

        let folders = ["/Applications",
                       "/System/Applications",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let target = "\(normalized).app"
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder),
                  let entry = entries.first(where: { $0.lowercased() == target }) else { continue }
            let url = URL(fileURLWithPath: folder).appendingPathComponent(entry)
            if await open(url) {
                return FileManager.default.displayName(atPath: url.path)
            }
        }
        return nil
    }

    private static func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }
}
