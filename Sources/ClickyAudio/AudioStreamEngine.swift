import AVFoundation
import Foundation
import os

/// One 20 ms wire chunk (320 samples @ 16 kHz) plus its capture timestamp (T0/T1 anchors,
/// Validation 01 §4.1). Feed `samples` to `GeminiLiveClient.sendAudioFrame(_:)` or
/// `pcmLittleEndian` to `sendAudio(_:)`.
public struct AudioInputChunk: Sendable {
    public let samples: [Int16]
    public let pcmLittleEndian: Data
    public let captureStart: ContinuousClock.Instant
    public init(samples: [Int16], pcmLittleEndian: Data, captureStart: ContinuousClock.Instant) {
        self.samples = samples; self.pcmLittleEndian = pcmLittleEndian; self.captureStart = captureStart
    }
}

/// Output jitter buffer decision logic (Validation 01 §3.1): playback starts after
/// `targetChunks` 20 ms slices; an underrun grows the target, a clean streak shrinks it.
/// Pure logic, unit-tested; the engine owns the state.
public struct JitterBufferPolicy: Equatable, Sendable {
    public static let chunkDurationMs = 20
    public static let minChunks = 1
    public static let maxChunks = 5
    public static let cleanChunksToShrink = 100
    public private(set) var targetChunks = 2
    public private(set) var underrunCount = 0
    private var cleanStreak = 0
    public init() {}
    public var targetMillis: Int { targetChunks * Self.chunkDurationMs }
    public func shouldStartPlayback(bufferedChunks: Int) -> Bool { bufferedChunks >= targetChunks }
    public mutating func recordDelivery(hadUnderrun: Bool) {
        if hadUnderrun {
            underrunCount += 1; cleanStreak = 0; targetChunks = min(targetChunks + 1, Self.maxChunks)
        } else {
            cleanStreak += 1
            if cleanStreak >= Self.cleanChunksToShrink {
                cleanStreak = 0; targetChunks = max(targetChunks - 1, Self.minChunks)
            }
        }
    }
}

/// Software echo fallback (spec §4.1; errata B9): while the AEC is still converging (first
/// ~300 ms of playback) drop mic frames whenever speaker energy is present. After the
/// window, hardware AEC owns the cancellation.
public struct AECMuteGate: Equatable, Sendable {
    public var convergenceWindowMs: Int
    public var speakerActivityThreshold: Float
    public init(convergenceWindowMs: Int = 300, speakerActivityThreshold: Float = 0.02) {
        self.convergenceWindowMs = convergenceWindowMs; self.speakerActivityThreshold = speakerActivityThreshold
    }
    public func shouldMute(msSincePlaybackStart: Int?, speakerLevel: Float) -> Bool {
        guard let elapsed = msSincePlaybackStart else { return false }
        return elapsed < convergenceWindowMs && speakerLevel >= speakerActivityThreshold
    }
}

/// 16-bit mono PCM sine — the audio self-test's model-audio stand-in (24 kHz path).
public enum AudioToneGenerator {
    public static func sinePCM(frequency: Double, durationSeconds: Double, sampleRate: Double,
                               amplitude: Float = 0.25) -> Data {
        let frameCount = Int((durationSeconds * sampleRate).rounded())
        var samples = [Int16](repeating: 0, count: frameCount)
        for index in 0..<frameCount {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            samples[index] = Int16((sin(phase) * Double(amplitude) * 32767).rounded())
        }
        var data = Data(capacity: samples.count * 2)
        samples.withUnsafeBufferPointer { input in
            guard let base = input.baseAddress else { return }
            base.withMemoryRebound(to: UInt8.self, capacity: samples.count * 2) { bytes in
                data.append(bytes, count: samples.count * 2)
            }
        }
        return data
    }
}

/// The acoustic core (spec §4.1): VoiceProcessingIO enabled while the engine is STOPPED
/// (errata B9/B10), a 1024-frame tap at the actual hardware rate, ONE long-lived
/// AVAudioConverter to 16 kHz Int16, exact 20 ms chunks, an adaptive 2-chunk output jitter
/// buffer, and the RMS mute gate during AEC convergence. Model audio (24 kHz PCM) plays
/// through this same engine so AEC has its echo reference — never bypass VPIO.
public final class AudioStreamEngine: @unchecked Sendable {
    public struct Configuration: Sendable {
        // Requested 1024 frames; macOS delivers its own size — measured 4800-frame
        // (~100 ms) buffers on macOS 27 during Task 10.3 bring-up (2026-10-06).
        public var tapBufferSize: AVAudioFrameCount = 1024
        public var wireSampleRate: Double = 16_000
        public var wireChunkFrames: Int = 320                  // 20 ms
        // Retained for plan-shape compatibility; the VPIO output anchor now uses the
        // input format's rate (macOS 27 requires matching client-side formats).
        public var outputSampleRate: Double = 48_000
        public var vad = LocalVADConfiguration.clickyDefault
        public var aecMuteGate = AECMuteGate()
        public init() {}
    }
    public struct DeviceChange: Sendable {
        public let inputSampleRate: Double
        public let outputSampleRate: Double
    }
    public enum AudioError: Error, Equatable {
        case voiceProcessingUnavailable(String), noInputDevice, converterUnavailable, engineStartFailed(String)
    }
    public var onInputChunk: (@Sendable (AudioInputChunk) -> Void)?
    public var onVADEvent: (@Sendable (LocalVADEvent, ContinuousClock.Instant) -> Void)?
    public var onDeviceChange: (@Sendable (DeviceChange) -> Void)?
    public var onError: (@Sendable (AudioError) -> Void)?

    private let configuration: Configuration
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let processingQueue = DispatchQueue(label: "com.clicky.audio.processing", qos: .userInitiated)
    private let lock = NSLock()
    /// Serializes engine lifecycle: `start()`, `stop()`, and `renegotiate()`'s queue block.
    /// Also owns `tapInstalled`. Lock order is always lifecycleLock → lock; no path takes
    /// `lock` and then `lifecycleLock`.
    private let lifecycleLock = NSLock()
    private let log = Logger(subsystem: "com.clicky.mac", category: "audio")
    // Installed/reset only inside `installInputTap()` while the engine is stopped (under
    // lifecycleLock); thereafter each field's access is as noted.
    private var converter: AVAudioConverter?              // written only by installInputTap(); then read on the tap thread
    private var playbackConverter: AVAudioConverter?      // processingQueue only
    private var playbackFormat: AVAudioFormat?
    private var pending16k: [Int16] = []                  // reset by installInputTap(); then read/written on the tap thread
    private var chunkStart: ContinuousClock.Instant?      // reset by installInputTap(); then read/written on the tap thread
    private var vad: LocalVAD                             // processingQueue only
    private var tapInstalled = false                      // lifecycleLock territory
    private var running = false
    private var observer: NSObjectProtocol?
    private var mutedChunks = 0
    private var jitter = JitterBufferPolicy()
    private var playbackSuppressed = false
    private var playbackPrimed = false
    private var playbackBuffered: [AVAudioPCMBuffer] = []
    private var playbackPartial = Data()
    private var playbackOutstanding = 0
    private var playbackStartedAt: ContinuousClock.Instant?
    private var lastSpeakerLevel: Float = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.vad = LocalVAD(configuration: configuration.vad)
    }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }
    public var isPlaybackActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return playbackOutstanding > 0 || !playbackBuffered.isEmpty
    }
    public var jitterTargetMillis: Int { lock.lock(); defer { lock.unlock() }; return jitter.targetMillis }
    public var playbackUnderrunCount: Int { lock.lock(); defer { lock.unlock() }; return jitter.underrunCount }
    public var mutedChunkCount: Int { lock.lock(); defer { lock.unlock() }; return mutedChunks }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Ordering is immutable (errata B9/B10): enable voice processing while the engine is
    /// stopped, read the actual formats, then start. Throws instead of silently running
    /// without AEC.
    public func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        lock.lock(); let alreadyRunning = running; lock.unlock()
        guard !alreadyRunning else { return }
        try startWithRetries()
        lock.lock(); running = true; player.play(); lock.unlock()
    }

    /// Runs the full graph + start sequence with bounded retries. macOS 27 VPIO
    /// (measured 2026-10-06) configures its aggregate asynchronously and passes through
    /// transient format states (0 Hz, 5↔7 channels) and reconfiguration windows where
    /// the AU refuses to initialize ("client-side input and output formats do not
    /// match", -10875). Requires `lifecycleLock`; must not be called with the state
    /// `lock` held. The caller sets `running`/`player.play()` on success.
    private func startWithRetries() throws {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                do { try engine.inputNode.setVoiceProcessingEnabled(true) }
                catch { throw AudioError.voiceProcessingUnavailable(String(describing: error)) }
                let inputFormat = try waitForStableInputFormat()
                try connectOutputAnchor(inputSampleRate: inputFormat.sampleRate)
                try prepareGraph(inputSampleRate: inputFormat.sampleRate)
                // Register before start(): the engine may stop itself right after start
                // ("iounit configuration changed") while the aggregate settles; the
                // observer must already be in place so the sweep-up renegotiate() runs.
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
                observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                  queue: nil) { [weak self] _ in self?.renegotiate() }
                engine.prepare()
                try engine.start()
                return
            } catch {
                lastError = error
                if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
                if engine.isRunning { engine.stop() }
                log.notice("audio engine start attempt \(attempt, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.4) }
            }
        }
        throw AudioError.engineStartFailed(String(describing: lastError))
    }

    public func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lock.lock()
        let wasRunning = running
        running = false
        guard wasRunning else { lock.unlock(); return }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        player.stop(); player.reset()
        lock.unlock()
    }

    /// macOS VPIO (measured 2026-10-06, macOS 27): the output node only comes online
    /// with an explicit mixer→output connection, and VPIO requires the client-side
    /// input and output sample rates to match ("client-side input and output formats
    /// do not match", -10875). The stereo client format therefore uses the input
    /// format's rate; the output node converts to the hardware rate.
    private func connectOutputAnchor(inputSampleRate: Double) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: inputSampleRate,
                                         channels: 2) else { throw AudioError.converterUnavailable }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
    }

    /// Bounded wait for `inputFormat(forBus: 0)` to be valid and stable across two
    /// consecutive reads. VPIO on macOS 27 reports transient 0 Hz / changing channel
    /// counts while its aggregate device configures (measured 2026-10-06). Requires
    /// `lifecycleLock`.
    private func waitForStableInputFormat() throws -> AVAudioFormat {
        let deadline = ContinuousClock.now + .seconds(2)
        var previous = engine.inputNode.inputFormat(forBus: 0)
        while ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            let current = engine.inputNode.inputFormat(forBus: 0)
            if current.sampleRate > 0, current.channelCount > 0,
               current.sampleRate == previous.sampleRate, current.channelCount == previous.channelCount {
                return current
            }
            previous = current
        }
        guard previous.sampleRate > 0, previous.channelCount > 0 else { throw AudioError.noInputDevice }
        return previous
    }

    /// Player→mixer connection plus the input tap at the current hardware format.
    /// Requires `lifecycleLock`; called from `start()` and `renegotiate()`.
    private func prepareGraph(inputSampleRate: Double) throws {
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate,
                                               channels: 1, interleaved: false) else { throw AudioError.converterUnavailable }
        lock.lock(); playbackFormat = outputFormat; lock.unlock()
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        try installInputTap()
    }

    /// MUST be called with `lifecycleLock` held (from `start()` or `renegotiate()`); it
    /// (re)writes `converter`, `pending16k`, and `chunkStart` while the engine is stopped.
    private func installInputTap() throws {
        let input = engine.inputNode
        let hardwareFormat = input.inputFormat(forBus: 0)   // actual rate AFTER enabling VP (errata B9)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else { throw AudioError.noInputDevice }
        // VPIO's input format is a multi-channel duplex format (5–7 ch on macOS 27).
        // AVAudioConverter silently outputs silence when downmixing it to mono without a
        // channel layout (measured 2026-10-06); all channels carry the same processed
        // signal, so tap at the hardware format and convert from a mono channel-0 copy.
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardwareFormat.sampleRate,
                                             channels: 1, interleaved: false),
              let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: configuration.wireSampleRate,
                                             channels: 1, interleaved: true),
              let newConverter = AVAudioConverter(from: monoFormat, to: wireFormat) else {
            throw AudioError.converterUnavailable
        }
        if tapInstalled { input.removeTap(onBus: 0) }
        converter = newConverter
        pending16k.removeAll(keepingCapacity: true)
        chunkStart = nil
        input.installTap(onBus: 0, bufferSize: configuration.tapBufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            self?.handleInput(buffer)
        }
        tapInstalled = true
    }

    // MARK: Input (tap thread → processingQueue)

    private func handleInput(_ buffer: AVAudioPCMBuffer) {
        guard let converter, buffer.frameLength > 0 else { return }
        guard let floatChannel = buffer.floatChannelData?[0] else {
            log.error("input buffer has no float channel data (format=\(String(describing: buffer.format), privacy: .public))")
            return
        }
        let frames = Int(buffer.frameLength)
        guard let monoSource = AVAudioPCMBuffer(pcmFormat: converter.inputFormat,
                                                frameCapacity: AVAudioFrameCount(frames)) else { return }
        monoSource.frameLength = AVAudioFrameCount(frames)
        if let destination = monoSource.floatChannelData?[0] {
            destination.update(from: floatChannel, count: frames)
        }
        let ratio = buffer.format.sampleRate / configuration.wireSampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) / ratio).rounded(.up) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var consumedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, statusPointer in
            if consumedInput { statusPointer.pointee = .noDataNow; return nil }
            consumedInput = true; statusPointer.pointee = .haveData
            return monoSource
        }
        guard conversionError == nil, status == .haveData || status == .inputRanDry,
              let channel = converted.int16ChannelData?[0], converted.frameLength > 0 else {
            log.error("input conversion failed: status=\(String(describing: status), privacy: .public) error=\(String(describing: conversionError), privacy: .public)")
            return
        }
        if pending16k.isEmpty {
            chunkStart = ContinuousClock.now - Duration.seconds(Double(buffer.frameLength) / buffer.format.sampleRate)
        }
        pending16k.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        drainWireChunks()
    }

    private func drainWireChunks() {
        while pending16k.count >= configuration.wireChunkFrames {
            guard let start = chunkStart else { break }
            let slice = Array(pending16k.prefix(configuration.wireChunkFrames))
            pending16k.removeFirst(configuration.wireChunkFrames)
            chunkStart = start + .milliseconds(JitterBufferPolicy.chunkDurationMs)
            processingQueue.async { [weak self] in self?.emit(slice, captureStart: start) }
        }
    }

    private func emit(_ samples: [Int16], captureStart: ContinuousClock.Instant) {
        lock.lock()
        let speakerLevel = lastSpeakerLevel
        let elapsed: Int? = playbackStartedAt.map { instant in
            let duration = ContinuousClock.now - instant
            return Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
        }
        lock.unlock()
        if configuration.aecMuteGate.shouldMute(msSincePlaybackStart: elapsed, speakerLevel: speakerLevel) {
            lock.lock(); mutedChunks += 1; lock.unlock()
            return
        }
        var pcm = Data(capacity: samples.count * 2)
        samples.withUnsafeBufferPointer { input in
            guard let base = input.baseAddress else { return }
            base.withMemoryRebound(to: UInt8.self, capacity: samples.count * 2) { bytes in
                pcm.append(bytes, count: samples.count * 2)
            }
        }
        onInputChunk?(AudioInputChunk(samples: samples, pcmLittleEndian: pcm, captureStart: captureStart))
        if let event = vad.process(samples: samples) { onVADEvent?(event, captureStart) }
    }

    // MARK: Output

    /// Call at the top of every model turn (or self-test run): re-enables playback after a
    /// cancel and re-primes the jitter buffer.
    public func beginPlaybackTurn() {
        lock.lock()
        playbackSuppressed = false; playbackPrimed = false
        playbackBuffered.removeAll(); playbackPartial.removeAll(keepingCapacity: true)
        if engine.isRunning, !player.isPlaying { player.play() }
        lock.unlock()
    }

    /// The kill-switch/barge-in panic path. Synchronous — the caller measures T7 from this
    /// return. Playback stays stopped until `beginPlaybackTurn()`.
    public func stopPlaybackNow() {
        lock.lock()
        playbackSuppressed = true; playbackPrimed = false; playbackBuffered.removeAll()
        playbackOutstanding = 0; playbackStartedAt = nil
        if player.engine != nil {
            player.stop(); player.reset()
            if engine.isRunning { player.play() }
        }
        lock.unlock()
    }

    /// Feed decoded 24 kHz PCM (one or more model audio chunks): sliced into 20 ms units,
    /// converted 24→48 kHz, gated by the adaptive jitter buffer.
    public func enqueuePlaybackPCM(_ data: Data, sampleRate: Double = 24_000) {
        guard sampleRate > 0, !data.isEmpty else { return }
        processingQueue.async { [weak self] in self?.handlePlayback(data, sampleRate: sampleRate) }
    }

    private func handlePlayback(_ data: Data, sampleRate: Double) {
        let sliceBytes = Int(sampleRate * Double(JitterBufferPolicy.chunkDurationMs) / 1000) * 2
        lock.lock()
        guard !playbackSuppressed else { lock.unlock(); return }
        playbackPartial.append(data)
        var slices: [Data] = []
        while playbackPartial.count >= sliceBytes {
            slices.append(playbackPartial.prefix(sliceBytes))
            playbackPartial.removeFirst(sliceBytes)
        }
        lock.unlock()
        for slice in slices { scheduleSlice(slice, sampleRate: sampleRate) }
    }

    private func scheduleSlice(_ slice: Data, sampleRate: Double) {
        let samples = Self.decodePCM16(slice)
        guard !samples.isEmpty, let buffer = makePlaybackBuffer(samples, sampleRate: sampleRate) else { return }
        let level = AudioLevel.rms(samples)                  // echo-reference level (24 kHz source)
        lock.lock()
        defer { lock.unlock() }
        guard !playbackSuppressed else { return }
        lastSpeakerLevel = level
        if playbackPrimed {
            if playbackOutstanding == 0 && !player.isPlaying {
                jitter.recordDelivery(hadUnderrun: true)
                log.notice("playback underrun — jitter target \(self.jitter.targetMillis, privacy: .public) ms")
            }
            schedule(buffer)
        } else {
            playbackBuffered.append(buffer)
            guard jitter.shouldStartPlayback(bufferedChunks: playbackBuffered.count) else { return }
            for buffered in playbackBuffered { schedule(buffered) }
            playbackBuffered.removeAll(keepingCapacity: true)
            playbackPrimed = true
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        if !player.isPlaying { player.play() }
        if playbackOutstanding == 0 { playbackStartedAt = ContinuousClock.now }
        playbackOutstanding += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Hop off the player callback thread before touching state, so `player.stop()`
            // under `lock` can never deadlock against a synchronous completion.
            self?.processingQueue.async { [weak self] in self?.playbackCompleted() }
        }
    }

    private func playbackCompleted() {
        lock.lock(); defer { lock.unlock() }
        playbackOutstanding = max(0, playbackOutstanding - 1)
        jitter.recordDelivery(hadUnderrun: false)
        if playbackOutstanding == 0 && playbackBuffered.isEmpty {
            playbackPrimed = false; playbackStartedAt = nil
        }
    }

    private func makePlaybackBuffer(_ samples: [Int16], sampleRate: Double) -> AVAudioPCMBuffer? {
        lock.lock(); let format = playbackFormat; lock.unlock()
        guard let format,
              let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                               channels: 1, interleaved: true),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        source.frameLength = AVAudioFrameCount(samples.count)
        if let destination = source.int16ChannelData?[0] {
            samples.withUnsafeBufferPointer { input in
                guard let base = input.baseAddress else { return }
                destination.update(from: base, count: samples.count)
            }
        }
        if playbackConverter == nil || playbackConverter?.inputFormat.sampleRate != sampleRate {
            playbackConverter = AVAudioConverter(from: sourceFormat, to: format)
        }
        guard let converter = playbackConverter else { return nil }
        let capacity = AVAudioFrameCount(Double(samples.count) * converter.outputFormat.sampleRate / sampleRate + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, pointer in
            if consumed { pointer.pointee = .noDataNow; return nil }
            consumed = true; pointer.pointee = .haveData
            return source
        }
        guard conversionError == nil, status == .haveData || status == .inputRanDry, output.frameLength > 0 else {
            log.error("playback conversion failed: status=\(String(describing: status), privacy: .public) error=\(String(describing: conversionError), privacy: .public)")
            return nil
        }
        return output
    }

    private static func decodePCM16(_ data: Data) -> [Int16] {
        var samples = [Int16](repeating: 0, count: data.count / 2)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return samples
    }

    // MARK: Device changes

    private func renegotiate() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.lifecycleLock.lock()
            self.lock.lock()
            let wasRunning = self.running
            self.playbackPrimed = false; self.playbackBuffered.removeAll()
            self.playbackPartial.removeAll(keepingCapacity: true)
            self.playbackOutstanding = 0; self.playbackStartedAt = nil
            self.lock.unlock()
            guard wasRunning else { self.lifecycleLock.unlock(); return }
            self.log.notice("AVAudioEngineConfigurationChange — re-negotiating formats")
            self.engine.stop()
            if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
            // Full VPIO reset for the new device set: the old mixer→output anchor pins a
            // stale client sample rate and keeps the unit from initializing its new
            // aggregate ("client-side input and output formats do not match", -10875,
            // measured 2026-10-06). Disable VP, drop the anchor, anchor at the plain input
            // rate, then let startWithRetries() re-enable VP and rebuild with matching
            // formats.
            self.engine.disconnectNodeOutput(self.engine.mainMixerNode)
            do { try self.engine.inputNode.setVoiceProcessingEnabled(false) }
            catch { self.log.notice("could not disable voice processing during reset: \(String(describing: error), privacy: .public)") }
            let plainInputRate = self.engine.inputNode.inputFormat(forBus: 0).sampleRate
            if plainInputRate > 0 {
                do { try self.connectOutputAnchor(inputSampleRate: plainInputRate) }
                catch { self.log.notice("could not re-anchor output during reset: \(String(describing: error), privacy: .public)") }
            }
            var deviceChange: DeviceChange?
            var restartError: AudioError?
            do {
                try self.startWithRetries()
                self.lock.lock(); self.player.play(); self.lock.unlock()
                deviceChange = DeviceChange(
                    inputSampleRate: self.engine.inputNode.inputFormat(forBus: 0).sampleRate,
                    outputSampleRate: self.engine.outputNode.outputFormat(forBus: 0).sampleRate)
                self.log.notice("audio engine restarted after device change")
            } catch {
                // A failed restart must not leave the tap installed while `running == false`.
                if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
                self.lock.lock(); self.running = false; self.lock.unlock()
                let message = String(describing: error)
                restartError = .engineStartFailed(message)
                self.log.error("audio engine could not restart after device change: \(message, privacy: .public)")
            }
            // Release the lifecycle lock before invoking user callbacks: a handler may
            // synchronously call start()/stop(), which would deadlock on the non-recursive lock.
            self.lifecycleLock.unlock()
            if let deviceChange { self.onDeviceChange?(deviceChange) }
            if let restartError { self.onError?(restartError) }
        }
    }
}
