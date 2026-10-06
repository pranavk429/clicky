import AppKit
import ClickyCore
import ClickyAudio
import ClickyInput
import ClickyOverlay
import os
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notice: String?
    private let state = AppState.shared
    private var hotKeys: GlobalHotKey?
    private var killSwitch: KillSwitchManager?
    private var audioSelfTest: AudioSelfTestRunner?
    private var demoRunner: ScriptedDemoRunner?
    private var wakeWord: WakeWordListener?
    private static let wakeWordEnabledKey = "clicky.wakeWordEnabled"
    /// Voice-activation preference, default ON. Read via `object(forKey:)` first:
    /// an absent key must mean "enabled", while `bool(forKey:)` alone would
    /// report the default as off.
    private var wakeWordEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.wakeWordEnabledKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: Self.wakeWordEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.wakeWordEnabledKey) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Clicky — voice cursor"
        statusItem = item
        rebuildMenu()
        NotificationCenter.default.addObserver(forName: .clickySessionStateChanged, object: nil, queue: .main) { [weak self] note in
            let state = note.object as? SessionState
            Task { @MainActor in
                // Re-arm the registered ⌘⇧X manager for every listening session: it
                // latches on the first trigger, so without this reset the second
                // kill-switch press never fires (spec §4.4 one-trigger-per-turn latch).
                if state == .listening { self?.killSwitch?.reset() }
                self?.syncWakeWordState(state)
                self?.rebuildMenu()
            }
        }
        PermissionsCenter.shared.startWatchdog()
        PermissionsCenter.shared.onRevocation = { [weak self] kind in
            Task { @MainActor in self?.setNotice("\(kind.displayName) permission was revoked — open Permissions & First-Run Setup.") }
        }
        if CommandLine.arguments.contains("--scripted-demo") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.runScriptedDemo()
            }
        }
        if CommandLine.arguments.contains("--live-demo") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                // Same path as the menu toggle; only start when idle/stopped so a
                // session already active at launch is never toggled off.
                guard let self, !self.state.session.isActive else { return }
                self.state.toggleSession()
            }
        }
        installHotKeys()
        OverlayWindowController.shared.start()
        SessionCoordinator.shared.onNotice = { [weak self] text in
            Task { @MainActor in self?.setNotice(text) }
        }
        SessionCoordinator.shared.observeAppState()
        if wakeWordEnabled { startWakeWordListener(announceIfUnsupported: true) }
    }
    @objc private func toggleSession() { state.toggleSession() }

    /// Voice activation: saying "Clicky" starts a session hands-free. The
    /// preference persists in UserDefaults; the listener runs on-device only.
    @objc private func toggleWakeWord() {
        wakeWordEnabled.toggle()
        if wakeWordEnabled {
            startWakeWordListener(announceIfUnsupported: true)
        } else {
            stopWakeWordListener()
        }
        rebuildMenu()
    }

    /// Start the on-device wake-word listener unless one is already running.
    /// Permission/availability failures surface as menu notices instead of
    /// silently leaving the preference on with nothing listening.
    private func startWakeWordListener(announceIfUnsupported: Bool = false) {
        guard wakeWord == nil else { return }
        guard WakeWordListener.isSupported else {
            if announceIfUnsupported { setNotice("Wake word is not supported on this Mac") }
            return
        }
        if !WakeWordListener.hasSpeechPermission {
            // First run: macOS only shows the Speech Recognition prompt from the
            // request call — ask, then retry once the user answers. A previously
            // denied state returns false immediately (no prompt).
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await WakeWordListener.requestSpeechPermission() {
                    self.startWakeWordListener(announceIfUnsupported: announceIfUnsupported)
                } else {
                    self.setNotice("Wake word needs Speech Recognition permission — System Settings → Privacy & Security → Speech Recognition")
                }
            }
            return
        }
        let listener = WakeWordListener()
        listener.onWake = {
            Task { @MainActor in
                // Start only when no session is active (idle/stopped); an active
                // session owns the mic and the toggle would stop it.
                if !AppState.shared.session.isActive { AppState.shared.toggleSession() }
            }
        }
        do {
            try listener.start()
        } catch {
            setNotice("Wake word unavailable (\(error)) — enable Speech Recognition in System Settings")
            return
        }
        wakeWord = listener
        // Enabled mid-session: the listener must not fight the session for the
        // mic, so start it (establishing the engine) then park it immediately.
        if state.session.isActive { listener.pause() }
    }

    private func stopWakeWordListener() {
        wakeWord?.stop()
        wakeWord = nil
    }

    /// Keep the wake-word listener on the opposite side of the mic from the
    /// session: paused while Clicky is listening/reconnecting, resumed once the
    /// session is idle or stopped. No-op while the preference is off.
    private func syncWakeWordState(_ state: SessionState?) {
        guard let state, wakeWordEnabled else { return }
        switch state {
        case .listening, .reconnecting: wakeWord?.pause()
        case .idle, .stopped: wakeWord?.resume()
        }
    }
    /// The text-command fallback (voice-first, not voice-only): opens the typed
    /// command panel, or points at the session toggle when there is no session
    /// to receive the text.
    @objc private func showTextCommand() {
        guard state.session.isActive else {
            setNotice("Start listening first (⌘⇧Space) — then type your command")
            return
        }
        TextCommandPanelController.shared.show { text in
            Task { @MainActor in await SessionCoordinator.shared.submitTypedCommand(text) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        wakeWord?.stop()
        Task { await SessionCoordinator.shared.stop(reason: .userToggle) }
    }
    @objc private func showPermissions() { PermissionsWindowController.shared.show() }
    @objc private func runScriptedDemo() {
        let runner = demoRunner ?? ScriptedDemoRunner()
        demoRunner = runner
        runner.start()
    }
    @objc private func stopScriptedDemo() {
        if let runner = demoRunner {
            Task { await runner.stop(reason: .userToggle) }
        }
    }
    func setNotice(_ text: String?) { notice = text; rebuildMenu() }
    private func rebuildMenu() {
        guard let item = statusItem else { return }
        item.button?.image = Self.icon(for: state.session)
        let menu = NSMenu()
        if let notice {
            let noticeItem = NSMenuItem(title: "⚠️ \(notice)", action: nil, keyEquivalent: "")
            noticeItem.isEnabled = false
            menu.addItem(noticeItem)
        }
        let status = NSMenuItem(title: Self.statusText(for: state.session), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: state.session.isActive ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleSession), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let wakeWordItem = NSMenuItem(title: "Wake Word (\"Clicky\"): \(wakeWordEnabled ? "On" : "Off")",
                                      action: #selector(toggleWakeWord), keyEquivalent: "")
        wakeWordItem.target = self
        menu.addItem(wakeWordItem)
        let typeCommand = NSMenuItem(title: "Type a Command…", action: #selector(showTextCommand), keyEquivalent: "")
        typeCommand.target = self
        menu.addItem(typeCommand)
        menu.addItem(.separator())
        let selfTest = NSMenuItem(title: "Run Audio Self-Test (30 s)…", action: #selector(runAudioSelfTest), keyEquivalent: "")
        selfTest.target = self
        menu.addItem(selfTest)
        let permissions = NSMenuItem(title: "Permissions & First-Run Setup…", action: #selector(showPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let runDemo = NSMenuItem(title: "Run Scripted Demo", action: #selector(runScriptedDemo), keyEquivalent: "")
        runDemo.target = self
        menu.addItem(runDemo)
        let stopDemo = NSMenuItem(title: "Stop Demo (Esc)", action: #selector(stopScriptedDemo), keyEquivalent: "")
        stopDemo.target = self
        menu.addItem(stopDemo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clicky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }
    private static func statusText(for state: SessionState) -> String {
        switch state {
        case .idle: return "Idle — mic off"
        case .listening: return "● Listening"
        case .reconnecting(let r): return "Reconnecting… (\(r))"
        case .stopped(let r): return "Stopped (\(r.rawValue))"
        }
    }
    private static func icon(for state: SessionState) -> NSImage? {
        switch state {
        case .idle, .stopped: return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Clicky idle")
        case .listening: return NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Clicky listening")
        case .reconnecting: return NSImage(systemSymbolName: "wifi.exclamationmark", accessibilityDescription: "Clicky reconnecting")
        }
    }

    private func installHotKeys() {
        let killSwitch = KillSwitchManager(hooks: KillSwitchManager.Hooks(
            stopPlayback: { [weak self] in self?.audioSelfTest?.stopPlaybackNow() },
            releaseSyntheticInput: { KillSwitchManager.releaseSyntheticInputNow() },
            presentBanner: { [weak self] text in Task { @MainActor in self?.setNotice(text) } },
            // Stop the scripted demo path; the live session's own kill-switch observer
            // stops it via the notification posted after these hooks. Must not write
            // `notice` — that would overwrite the kill-switch banner presented above.
            stopSession: { [weak self] in Task { @MainActor in
                self?.stopScriptedDemo()
            } }))
        self.killSwitch = killSwitch
        let killStatus = killSwitch.registerKillHotKey()
        if killStatus != noErr { setNotice("⌘⇧X could not register (OSStatus \(killStatus))") }
        let sessionToggle = GlobalHotKey(hotKeys: [.sessionToggle]) { _ in
            Task { @MainActor in AppState.shared.toggleSession() }
        }
        let toggleStatus = sessionToggle.register()
        if toggleStatus != noErr { setNotice("⌘⇧Space could not register (OSStatus \(toggleStatus))") }
        hotKeys = sessionToggle
    }

    @objc private func runAudioSelfTest() {
        guard let killSwitch else { setNotice("Kill switch is not initialized"); return }
        if audioSelfTest == nil { audioSelfTest = AudioSelfTestRunner(killSwitch: killSwitch) }
        audioSelfTest?.start()
    }
}

/// Dev/diagnostic harness for the Task 10.2 audio bring-up checks: plays a 440 Hz tone
/// through the real VPIO graph like model audio (24 kHz PCM), logs VAD onsets + stop
/// latency, and survives a live device switch.
fileprivate final class AudioSelfTestRunner: @unchecked Sendable {
    private let engine = AudioStreamEngine()
    private let killSwitch: KillSwitchManager
    private let log = Logger(subsystem: "com.clicky.mac", category: "audio-selftest")
    private var toneTimer: Timer?
    private var endTimer: Timer?
    private var inputChunkCount = 0
    private var onsetCount = 0
    init(killSwitch: KillSwitchManager) { self.killSwitch = killSwitch }

    func start() {
        guard !engine.isRunning else { return }
        killSwitch.reset()
        engine.beginPlaybackTurn()
        engine.onInputChunk = { [weak self] _ in Task { @MainActor in self?.noteInputChunk() } }
        engine.onVADEvent = { [weak self] event, captureStart in
            Task { @MainActor in self?.noteVAD(event: event, captureStart: captureStart) }
        }
        engine.onDeviceChange = { [weak self] change in
            Task { @MainActor in
                self?.log.notice("selftest device change: input \(change.inputSampleRate, privacy: .public) Hz")
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor in self?.log.error("selftest engine error: \(String(describing: error), privacy: .public)") }
        }
        do { try engine.start() } catch {
            log.error("selftest could not start: \(String(describing: error), privacy: .public)")
            return
        }
        log.notice("selftest start — 30 s tone; expect 0 onsets in silence, ≥1 on speech")
        enqueueToneSecond()
        toneTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.enqueueToneSecond() }
        endTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stopPlaybackNow() { engine.stopPlaybackNow() }

    func stop() {
        toneTimer?.invalidate(); toneTimer = nil
        endTimer?.invalidate(); endTimer = nil
        engine.stop()
        log.notice("selftest end — inputChunks=\(self.inputChunkCount, privacy: .public) onsets=\(self.onsetCount, privacy: .public)")
    }

    private func enqueueToneSecond() {
        engine.enqueuePlaybackPCM(AudioToneGenerator.sinePCM(frequency: 440, durationSeconds: 1.0, sampleRate: 24_000),
                                  sampleRate: 24_000)
    }

    private func noteInputChunk() {
        inputChunkCount += 1
        if inputChunkCount % 50 == 0 {
            log.notice("selftest progress — chunks=\(self.inputChunkCount, privacy: .public) onsets=\(self.onsetCount, privacy: .public)")
        }
    }

    private func noteVAD(event: LocalVADEvent, captureStart: ContinuousClock.Instant) {
        switch event {
        case .speechOnset:
            onsetCount += 1
            log.notice("selftest VAD onset #\(self.onsetCount, privacy: .public)")
            killSwitch.triggerBargeIn(source: .voiceOnset, onset: captureStart)
        case .speechEnded:
            log.notice("selftest VAD speech ended")
        }
    }
}
