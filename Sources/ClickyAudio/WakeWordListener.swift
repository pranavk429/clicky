// Sources/ClickyAudio/WakeWordListener.swift
import AVFoundation
import Foundation
import os
import Speech

/// Errors thrown by `WakeWordListener.start()`.
public enum WakeWordError: Error, Equatable, Sendable {
    /// Speech Recognition permission is not granted
    /// (`SFSpeechRecognizer.authorizationStatus() != .authorized`).
    case permissionDenied
    /// The recognizer is unavailable or cannot run on-device. The listener NEVER
    /// falls back to server-side recognition (privacy requirement).
    case onDeviceUnavailable
    /// No usable audio input device.
    case noInputDevice
    /// `AVAudioEngine` refused to start.
    case engineStartFailed(String)
}

/// Pure debounce helper: the first match fires; matches inside `interval` afterwards
/// are swallowed. One spoken wake word produces many partial transcripts, so this is
/// what keeps `onWake` to a single call per utterance.
struct WakeWordDebouncer: Equatable, Sendable {
    let interval: TimeInterval
    private(set) var lastFire: Date?

    init(interval: TimeInterval) { self.interval = max(0, interval) }

    mutating func shouldFire(now: Date) -> Bool {
        if let lastFire, now.timeIntervalSince(lastFire) < interval { return false }
        lastFire = now
        return true
    }

    mutating func reset() { lastFire = nil }
}

/// On-device wake-word gate for hands-free session start.
///
/// While idle, a plain `AVAudioEngine` tap feeds an `SFSpeechAudioBufferRecognitionRequest`
/// with `requiresOnDeviceRecognition = true`; when a partial transcript contains one of
/// the configured variants, `onWake` fires once (debounced). Privacy posture:
/// - No server fallback: if on-device recognition is unsupported, `start()` throws
///   `WakeWordError.onDeviceUnavailable` and `isSupported` is `false`.
/// - Audio lives only in memory and is dropped after the recognizer consumes it;
///   nothing is written to disk and transcripts are never logged (only the wake hit).
///
/// Threading: engine and recognition lifecycle run on a private serial queue;
/// `onWake` is invoked on that queue — hop to `MainActor` at the wiring site.
/// `start()`/`pause()`/`resume()`/`stop()` may be called from any thread, including
/// `MainActor`, and are safe to repeat.
public final class WakeWordListener: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Normalized lowercase variants; a transcript matches when it contains one.
        public var phrases: [String]
        /// After a wake fires, further matches are ignored for this long.
        public var debounceSeconds: TimeInterval
        public init(phrases: [String] = WakeWordListener.defaultPhrases,
                    debounceSeconds: TimeInterval = 2.0) {
            self.phrases = phrases
            self.debounceSeconds = debounceSeconds
        }
    }

    /// Canonical "Clicky" plus the spellings `SFSpeechRecognizer` commonly returns for
    /// /ˈklɪki/ — homophone spellings ("cliquey"), Indic-accent vowel drift
    /// ("cliki"/"clicki"/"cliqi"), c→k hardening ("klicky"), and a recognizer word split
    /// ("click e"). `"click"` is deliberately absent: it is an ordinary command word,
    /// and because matching is `transcript.contains(phrase)`, including it would wake on
    /// unrelated speech. All variants are lowercase and punctuation-free because
    /// transcripts are normalized before matching.
    public static let defaultPhrases: [String] = [
        "clicky",    // canonical
        "cliquey",   // homophone spelling
        "cliquy",    // homophone spelling
        "cliki",     // Indic-accent vowel drift
        "clicki",    // Indic-accent vowel drift
        "klicky",    // c→k hardening
        "cliqy",     // clipped spelling
        "click e",   // recognizer splits the word
        "cliqi",     // q/i drift
    ]

    /// The wake recognizer is pinned to en-US — the locale with the broadest on-device
    /// asset coverage — and the phrase list absorbs accent drift.
    private static let recognizerLocale = Locale(identifier: "en-US")

    /// `true` when the recognizer is available and on-device recognition is
    /// supported for the wake locale — a pure capability check. Permission is
    /// deliberately NOT included (`hasSpeechPermission` / `requestSpeechPermission`
    /// cover that): including it made the launch path skip the permission request,
    /// so the first-run TCC prompt could never be reached and the wake word
    /// silently never started.
    public static var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: recognizerLocale),
              recognizer.isAvailable else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    /// `true` when the user has authorized Speech Recognition.
    public static var hasSpeechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Requests Speech Recognition permission (no prompt if already decided) and resolves
    /// to the post-request authorization state. Call from `MainActor`; the continuation
    /// resumes on an arbitrary queue.
    @discardableResult
    public static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Fired on the listener's private serial queue when the wake phrase is heard.
    /// Hop to `MainActor` at the wiring site.
    public var onWake: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return wakeHandler }
        set { lock.lock(); defer { lock.unlock() }; wakeHandler = newValue }
    }

    private enum State { case stopped, running, paused }

    private let configuration: Configuration
    private let normalizedPhrases: [String]
    private let recognizer: SFSpeechRecognizer?
    private let log = Logger(subsystem: "com.clicky.mac", category: "wake-word")

    /// Serializes engine + recognition lifecycle; owns `state`, `task`, `engine`,
    /// `tapInstalled`, `recognitionGeneration`, and `debouncer`.
    private let queue = DispatchQueue(label: "com.clicky.wakeword.listener", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()
    /// Guards `activeRequest` (read on the audio tap thread) and `wakeHandler`
    /// (set from any thread at wiring time).
    private let lock = NSLock()

    private var wakeHandler: (@Sendable () -> Void)?
    private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var state: State = .stopped
    private var tapInstalled = false
    private var recognitionGeneration = 0
    private var debouncer: WakeWordDebouncer

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.normalizedPhrases = configuration.phrases
            .map(Self.normalizeTranscript)
            .filter { !$0.isEmpty }
        self.debouncer = WakeWordDebouncer(interval: configuration.debounceSeconds)
        self.recognizer = SFSpeechRecognizer(locale: Self.recognizerLocale)
        queue.setSpecific(key: queueKey, value: 1)
        if let recognizer {
            let operationQueue = OperationQueue()
            operationQueue.underlyingQueue = queue
            operationQueue.maxConcurrentOperationCount = 1
            recognizer.queue = operationQueue
        }
    }

    deinit { stop() }

    // MARK: Lifecycle

    /// Starts idle listening. Idempotent while running. Throws when Speech Recognition
    /// permission is missing (`permissionDenied`) or on-device recognition is not
    /// available (`onDeviceUnavailable`) — never falls back to server recognition.
    public func start() throws {
        guard Self.hasSpeechPermission else { throw WakeWordError.permissionDenied }
        guard Self.isSupported else { throw WakeWordError.onDeviceUnavailable }
        try syncOnQueue { try startLocked() }
    }

    /// Stops recognition while a session owns the microphone. No-op unless running.
    public func pause() {
        syncOnQueue {
            guard state == .running else { return }
            teardownLocked()
            state = .paused
            log.notice("wake listener paused (session owns the mic)")
        }
    }

    /// Re-arms after `pause()`. No-op unless paused (a `stop()`ed listener needs `start()`).
    public func resume() {
        syncOnQueue {
            guard state == .paused else { return }
            state = .running
            do {
                try startEngineAndRecognitionLocked()
                log.notice("wake listener resumed")
            } catch {
                state = .paused
                log.error("wake listener resume failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Full teardown; `start()` may be called again afterwards. Safe to call repeatedly.
    public func stop() {
        syncOnQueue {
            guard state != .stopped else { return }
            teardownLocked()
            state = .stopped
            debouncer.reset()
            log.notice("wake listener stopped")
        }
    }

    // MARK: Matching (pure; no speech APIs)

    /// Pure matcher used by tests: `true` when the normalized transcript contains any
    /// configured phrase. Matching is `contains`, deliberately permissive — precision
    /// comes from the phrase list (`"click"` is absent), and the debounce keeps one
    /// utterance from firing twice. Consequence, accepted: `"unclicky"` contains
    /// `"clicky"` and DOES match; missing a real wake costs more than this exotic false
    /// positive, and the session/confirmation gates still contain any unintended action.
    internal func matchesWakePhrase(_ transcript: String) -> Bool {
        let normalized = Self.normalizeTranscript(transcript)
        guard !normalized.isEmpty else { return false }
        return normalizedPhrases.contains { normalized.contains($0) }
    }

    /// Lowercase, replace every non-alphanumeric scalar with a space, drop empty runs,
    /// and join with single spaces. Non-Latin alphanumerics pass through untouched and
    /// simply do not match the Latin variants.
    internal static func normalizeTranscript(_ transcript: String) -> String {
        transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Queue-confined internals

    private func syncOnQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return try work() }
        return try queue.sync(execute: work)
    }

    private func startLocked() throws {
        guard state != .running else { return }   // idempotent
        state = .running                          // also revives a paused/stopped listener
        debouncer.reset()
        do {
            try startEngineAndRecognitionLocked()
            log.notice("wake listener started (on-device only)")
        } catch {
            teardownLocked()
            state = .stopped
            throw error
        }
    }

    private func startEngineAndRecognitionLocked() throws {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw WakeWordError.onDeviceUnavailable
        }
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw WakeWordError.noInputDevice }
        if !tapInstalled {
            // Feed hardware-format tap buffers straight to the recognizer: the request
            // converts internally, so no 16 kHz downmix is needed while idle. Voice
            // processing stays off — AEC belongs to the live session engine, not the
            // idle wake gate.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.appendToActiveRequest(buffer)
            }
            tapInstalled = true
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
            throw WakeWordError.engineStartFailed(error.localizedDescription)
        }
        startRecognitionTaskLocked()
    }

    private func appendToActiveRequest(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = activeRequest
        lock.unlock()
        request?.append(buffer)
    }

    private func startRecognitionTaskLocked() {
        guard state == .running else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            // On-device support can disappear (e.g. language assets removed). Never fall
            // back to the server; retry later in case support returns.
            queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.state == .running, self.task == nil else { return }
                self.startRecognitionTaskLocked()
            }
            return
        }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true     // privacy: never server recognition
        request.shouldReportPartialResults = true      // wake fires on the first partial hit
        lock.lock(); activeRequest = request; lock.unlock()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            // Extract Sendable values on the framework's callback queue; transcripts are
            // never logged, only matched.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDescription = error.map { String(describing: $0) }
            self.queue.async {
                self.handleRecognition(generation: generation, transcript: transcript,
                                       isFinal: isFinal, errorDescription: errorDescription)
            }
        }
    }

    private func handleRecognition(generation: Int, transcript: String?, isFinal: Bool,
                                   errorDescription: String?) {
        guard generation == recognitionGeneration, state == .running else { return }
        if let transcript { handleTranscriptLocked(transcript) }
        guard isFinal || errorDescription != nil else { return }
        // SFSpeech tasks self-terminate after ~1 min or a stretch of silence; restart
        // transparently while the listener is running.
        task = nil
        lock.lock(); activeRequest = nil; lock.unlock()
        if let errorDescription {
            log.debug("recognition task ended: \(errorDescription, privacy: .public); restarting")
        }
        scheduleRestartLocked(after: errorDescription == nil ? 0.2 : 1.0)
    }

    private func scheduleRestartLocked(after delay: TimeInterval) {
        guard state == .running else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.state == .running, self.task == nil else { return }
            self.startRecognitionTaskLocked()
        }
    }

    private func handleTranscriptLocked(_ transcript: String) {
        guard matchesWakePhrase(transcript) else { return }
        guard debouncer.shouldFire(now: Date()) else { return }
        log.notice("wake phrase detected")
        lock.lock()
        let handler = wakeHandler
        lock.unlock()
        handler?()
    }

    private func teardownLocked() {
        recognitionGeneration += 1            // invalidate in-flight recognition callbacks
        task?.cancel()
        task = nil
        lock.lock(); activeRequest = nil; lock.unlock()
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            if engine.isRunning { engine.stop() }
        }
    }
}
