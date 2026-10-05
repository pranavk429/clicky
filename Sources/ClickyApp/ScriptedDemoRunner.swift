import AppKit
import Carbon.HIToolbox
import ClickyCore
import ClickyGemini
import ClickyOverlay
import Foundation

/// Runs the user-approved demo slice: a scripted server transport feeding a real
/// `GeminiLiveClient` over the real Ghost Cursor overlay. No network, no audio,
/// no AX and no event synthesis — only the transport is scripted.
@MainActor
final class ScriptedDemoRunner {
    private let overlay = GhostCursorController()
    private var client: GeminiLiveClient?
    private var mock: MockSession?
    private var driverTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var hotKey: EscapeHotKey?
    private var running = false

    /// The demo's scripted server frames as a `MockSession` scenario. Each frame's
    /// `afterMs` is the delta from the previous frame, so the old absolute beats
    /// (0.5, 1.2, 2.6, 7.0 s) reproduce as 500 + 700 + 1400 + 4400 ms.
    private static let scenarioJSON = #"""
    {
      "name": "demo-preview-actions",
      "frames": [
        { "afterMs": 500,  "json": "{\"setupComplete\":{}}" },
        { "afterMs": 700,  "json": "{\"serverContent\":{\"modelTurn\":{\"parts\":[{\"inlineData\":{\"data\":\"AA==\",\"mimeType\":\"audio/pcm;rate=24000\"}}]}}}" },
        { "afterMs": 1400, "json": "{\"toolCall\":{\"functionCalls\":[{\"id\":\"demo-fc-1\",\"name\":\"preview_action\",\"args\":{\"target\":{\"x\":0.5,\"y\":0.42},\"label\":\"Save करो\"}}]}}" },
        { "afterMs": 4400, "json": "{\"toolCall\":{\"functionCalls\":[{\"id\":\"demo-fc-2\",\"name\":\"preview_action\",\"args\":{\"target\":{\"x\":0.3,\"y\":0.62},\"label\":\"Type: नमस्ते\"}}]}}" }
      ]
    }
    """#

    func start() {
        guard !running else { return }
        guard let mock = try? MockSession(scenarioJSON: Self.scenarioJSON) else {
            overlay.showOverlay()
            overlay.setStatus("Demo scenario invalid — stopped")
            return
        }
        running = true
        cleanupTask?.cancel()
        cleanupTask = nil
        overlay.hideOverlay()   // clear a stopped banner left from a quick re-run
        overlay.showOverlay()
        overlay.setStatus("Clicky demo — scripted server, real client")

        self.mock = mock

        let client = GeminiLiveClient(
            transportFactory: { mock },
            setupFactory: { _ in GeminiSetupBuilder.make(systemInstruction: "Demo.") },
            toolHandler: DemoToolHandler(overlay: overlay),
            onServerContent: { [weak self] content in
                Task { @MainActor in self?.handleServerContent(content) }
            },
            onNotice: { [weak self] note in
                Task { @MainActor in self?.overlay.setStatus(note) }
            },
            onMarker: { [weak self] marker in
                Task { @MainActor in self?.showMarker(marker) }
            })
        self.client = client

        driverTask = Task { [weak self] in
            // The scenario's four frames land at 0.5 + 0.7 + 1.4 + 4.4 = 7.0 s;
            // hold 3 s more (7.0 + 3.0 = ≈10.0 s) so the last preview finishes,
            // then stop. `MockSession` paces each frame by its own `afterMs`.
            do { try await Task.sleep(for: .seconds(10.0)) } catch { return }
            if Task.isCancelled { return }
            await self?.stop(reason: .userToggle)
        }

        let hotKey = EscapeHotKey { [weak self] in
            Task { @MainActor in await self?.stop(reason: .killSwitch) }
        }
        hotKey.install(GetApplicationEventTarget())
        self.hotKey = hotKey

        connectTask = Task { [weak self] in
            do {
                try await client.start()
                guard let self, self.running else { return }
                self.overlay.setStatus("Ready (scripted)")
            } catch {
                guard let self, self.running else { return }
                self.overlay.setStatus("Demo connection failed — stopped")
                await self.stop(reason: .networkFailure)
            }
        }
    }

    /// Idempotent: the first caller wins, later callers (including Esc) are no-ops.
    func stop(reason: StopReason) async {
        guard running else { return }
        running = false
        driverTask?.cancel()
        driverTask = nil
        connectTask?.cancel()
        connectTask = nil
        hotKey?.uninstall()
        hotKey = nil
        if let client {
            await client.stop(reason: reason)
        }
        client = nil
        mock = nil
        overlay.dismissConfirmation()
        overlay.showStopped(reason == .killSwitch ? "STOPPED — local stop (no network)" : "Demo complete")
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.overlay.hideOverlay()
        }
    }

    // MARK: HUD

    private func showMarker(_ marker: GeminiMarker) {
        switch marker {
        case .firstAudioFrameReceived: overlay.setStatus("T4 · first audio")
        case .interruptedReceived: overlay.setStatus("T6 · interrupted")
        case .toolCallReceived: overlay.setStatus("T8 · tool call → preview")
        case .toolResponseSent: overlay.setStatus("T12 · response sent")
        case .audioStreamEndSent, .toolCallDropped: break
        }
    }

    private func handleServerContent(_ content: GeminiServerContent) {
        if content.interrupted == true {
            overlay.setStatus("T6 · interrupted")
        }
        if !content.audioBase64Chunks.isEmpty {
            overlay.setStatus("T4 · first audio")
        }
    }
}

/// Executes `preview_action` by moving the Ghost Cursor and flashing a
/// confirmation gate. It never clicks, types, sends a network request or reads
/// the accessibility tree — the action is a preview only.
private struct DemoToolHandler: GeminiToolHandling {
    let overlay: GhostCursorController

    func execute(_ call: GeminiToolCall.FunctionCall) async throws -> GeminiToolHandlerResult {
        guard call.name == "preview_action",
              let args = call.args,
              case .object(let target)? = args["target"],
              case .number(let x)? = target["x"],
              case .number(let y)? = target["y"],
              case .string(let label)? = args["label"] else {
            return Self.errorResult
        }

        let points = await MainActor.run { () -> (cg: CGPoint, appKit: CGPoint)? in
            guard let screen = NSScreen.main ?? NSScreen.screens.first,
                  let primary = NSScreen.screens.first else { return nil }
            let primaryHeight = primary.frame.height
            let geometry = DisplayGeometry(id: 0,
                                           cgFrame: CoordinateMath.cgFrame(fromAppKit: screen.frame,
                                                                          primaryHeight: primaryHeight),
                                           appKitFrame: screen.frame,
                                           scaleFactor: screen.backingScaleFactor)
            let cg = CoordinateMath.cgPoint(fromNormalized: CGPoint(x: x, y: y), on: geometry)
            let appKit = CoordinateMath.appKitPoint(fromCG: cg, primaryHeight: primaryHeight)
            return (cg, appKit)
        }
        guard let points else { return Self.errorResult }

        await overlay.setIntent(label)
        await overlay.moveCursor(to: points.appKit, duration: 0.8)
        await overlay.showConfirmation("Confirm? बोलो — हाँ")
        try? await Task.sleep(for: .seconds(1.2))
        await overlay.dismissConfirmation()
        await overlay.flashAction("preview only — nothing clicked")
        return GeminiToolHandlerResult(payload: .object(["status": .string("previewed")]),
                                       scheduling: .whenIdle)
    }

    private static let errorResult = GeminiToolHandlerResult(
        payload: .object(["status": .string("error")]), scheduling: .interrupted)
}

/// The demo's local stop path: a Carbon global hotkey on Esc. The C handler is a
/// non-capturing closure that resolves the instance from its user-data pointer.
private final class EscapeHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: @Sendable () -> Void

    init(onFire: @escaping @Sendable () -> Void) {
        self.onFire = onFire
    }

    func install(_ target: EventTargetRef) {
        guard hotKeyRef == nil, handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(target,
                            { _, _, userData in
                                guard let userData else { return noErr }
                                let hotKey = Unmanaged<EscapeHotKey>.fromOpaque(userData).takeUnretainedValue()
                                hotKey.onFire()
                                return noErr
                            },
                            1, &eventType, selfPointer, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4B59) /* 'CLKY' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, target, 0, &hotKeyRef)
    }

    func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit { uninstall() }
}
