import CoreGraphics
import Foundation
import os

/// The local-first stop path (spec §4.4; Validation 01 §2.3). Two triggers converge here:
/// the energy-onset VAD (primary — no server round-trip) and the ⌘⇧X Carbon chord. Each
/// path owns its own one-shot latch per turn: a voice barge-in stops playback only, while
/// the hardware kill switch always runs its full stop sequence — an emergency stop must
/// never be masked by a barge-in that already latched. `isInterrupted` is fail-closed: it
/// reads true once either latch has flipped, BEFORE any hook runs, so the safety layer
/// fails closed; the server `interrupted` frame is confirmation only. `reset()` re-arms
/// both latches at the start of each turn.
public final class KillSwitchManager: @unchecked Sendable {
    public enum Source: String, Equatable, Sendable {
        case voiceOnset, hotKey, menuBar
        public var displayName: String {
            switch self {
            case .voiceOnset: return "voice onset"
            case .hotKey: return "⌘⇧X"
            case .menuBar: return "menu"
            }
        }
    }

    /// Effects supplied by the app. Hooks run synchronously inside the trigger (the stop
    /// path has a <150 ms budget); UI hooks hop to the main queue themselves.
    public struct Hooks {
        public var stopPlayback: () -> Void
        public var releaseSyntheticInput: () -> Void
        public var presentBanner: (String) -> Void
        public var stopSession: () -> Void
        public init(stopPlayback: @escaping () -> Void, releaseSyntheticInput: @escaping () -> Void,
                    presentBanner: @escaping (String) -> Void, stopSession: @escaping () -> Void) {
            self.stopPlayback = stopPlayback
            self.releaseSyntheticInput = releaseSyntheticInput
            self.presentBanner = presentBanner
            self.stopSession = stopSession
        }
    }

    /// Posted after every trigger (Chunk 11 shows the stopped banner; Chunk 12 drops queued
    /// tool calls). `object` is the `Source`.
    public static let notificationName = Notification.Name("clickyKillSwitchFired")

    private let hooks: Hooks
    private let lock = NSLock()
    private let log = Logger(subsystem: "com.clicky.mac", category: "barge-in")
    private var bargeInLatched = false
    private var killSwitchFired = false
    private var lastSource: Source?
    private var lastLatencyMs: Double?
    private var hotKey: GlobalHotKey?

    public init(hooks: Hooks) { self.hooks = hooks }

    public var isInterrupted: Bool {
        lock.lock(); defer { lock.unlock() }
        return bargeInLatched || killSwitchFired
    }
    public var lastTriggerSource: Source? { lock.lock(); defer { lock.unlock() }; return lastSource }
    /// T7−T1 when the caller supplies the onset instant; nil for the hotkey path.
    public var lastBargeInMilliseconds: Double? { lock.lock(); defer { lock.unlock() }; return lastLatencyMs }

    /// Registers ⌘⇧X. Main thread only (Carbon `RegisterEventHotKey`); repeated calls are
    /// safe — `GlobalHotKey.register()` is idempotent. The session-toggle chord is
    /// registered by the app.
    @discardableResult
    public func registerKillHotKey() -> OSStatus {
        lock.lock()
        let hotKey = self.hotKey ?? GlobalHotKey(hotKeys: [.killSwitch]) { [weak self] action in
            guard action == .killSwitch else { return }
            self?.triggerKillSwitch(source: .hotKey)
        }
        self.hotKey = hotKey
        lock.unlock()
        return hotKey.register()
    }

    /// Voice path: stop playback and clear queued playback/actions. Returns false while
    /// already interrupted — one barge-in per turn, and none after a kill switch.
    @discardableResult
    public func triggerBargeIn(source: Source = .voiceOnset, onset: ContinuousClock.Instant? = nil) -> Bool {
        guard latchBargeIn() else { return false }
        hooks.stopPlayback()
        record(source: source, onset: onset)
        NotificationCenter.default.post(name: Self.notificationName, object: source)
        return true
    }

    /// Hardware path: barge-in + release synthetic input + banner + session stop. Runs its
    /// full hook sequence even when a voice barge-in already latched this turn — the
    /// emergency stop must never be masked. A second kill switch before `reset()` is a no-op.
    @discardableResult
    public func triggerKillSwitch(source: Source) -> Bool {
        guard latchKillSwitch() else { return false }
        hooks.stopPlayback()
        hooks.releaseSyntheticInput()
        hooks.presentBanner("Clicky stopped (\(source.displayName))")
        hooks.stopSession()
        record(source: source, onset: nil)
        NotificationCenter.default.post(name: Self.notificationName, object: source)
        return true
    }

    /// Re-arm both paths for the next turn.
    public func reset() {
        lock.lock()
        bargeInLatched = false
        killSwitchFired = false
        lock.unlock()
    }

    /// One barge-in per turn; blocked once interrupted (including after a kill switch).
    private func latchBargeIn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !bargeInLatched, !killSwitchFired else { return false }
        bargeInLatched = true
        return true
    }

    /// One kill switch per turn, independent of the barge-in latch.
    private func latchKillSwitch() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !killSwitchFired else { return false }
        killSwitchFired = true
        return true
    }

    private func record(source: Source, onset: ContinuousClock.Instant?) {
        var latency: Double?
        if let onset {
            let duration = ContinuousClock.now - onset
            latency = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        lock.lock(); lastSource = source; lastLatencyMs = latency; lock.unlock()
        if let latency {
            log.notice("local stop fired from \(source.rawValue, privacy: .public): \(latency, privacy: .public) ms from onset")
        } else {
            log.notice("local stop fired from \(source.rawValue, privacy: .public)")
        }
    }

    /// Release any synthetically held modifiers and post mouse-up so no drag or modifier
    /// stays stuck (spec §4.4; errata C4).
    public static func releaseSyntheticInputNow() { SyntheticInputPanic.releaseAll() }
}

/// Panic release: key-up for every modifier keycode, mouse-up for every button. Ending a
/// modifier state is always the safe direction; a key-up for a key that is not held is inert.
public enum SyntheticInputPanic {
    public static let modifierKeyCodes: [CGKeyCode] = [55, 56, 58, 59, 60, 61, 62, 63]
    public static func releaseAll() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyCode in modifierKeyCodes {
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
        }
        guard let location = CGEvent(source: nil)?.location else { return }
        for button in [CGMouseButton.left, .right, .center] {
            let type: CGEventType
            switch button {
            case .left: type = .leftMouseUp
            case .right: type = .rightMouseUp
            default: type = .otherMouseUp
            }
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button)?
                .post(tap: .cghidEventTap)
        }
    }
}
