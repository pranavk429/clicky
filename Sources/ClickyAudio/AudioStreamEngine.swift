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
        public var tapBufferSize: AVAudioFrameCount = 1024     // ~21 ms @ 48 kHz
        public var wireSampleRate: Double = 16_000
        public var wireChunkFrames: Int = 320                  // 20 ms
        public var outputSampleRate: Double = 48_000           // 24→48 on output
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
    private let log = Logger(subsystem: "com.clicky.mac", category: "audio")
    private var converter: AVAudioConverter?              // tap thread only
    private var playbackConverter: AVAudioConverter?      // processingQueue only
    private var playbackFormat: AVAudioFormat?
    private var pending16k: [Int16] = []                  // tap thread only
    private var chunkStart: ContinuousClock.Instant?      // tap thread only
    private var vad: LocalVAD                             // processingQueue only
    private var tapInstalled = false
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
    public func mutedChunkCount() -> Int { lock.lock(); defer { lock.unlock() }; return mutedChunks }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Ordering is immutable (errata B9/B10): enable voice processing while the engine is
    /// stopped, read the actual formats, then start. Throws instead of silently running
    /// without AEC.
    public func start() throws {
        lock.lock(); let alreadyRunning = running; lock.unlock()
        guard !alreadyRunning else { return }
        do { try engine.inputNode.setVoiceProcessingEnabled(true) }
        catch { throw AudioError.voiceProcessingUnavailable(String(describing: error)) }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: configuration.outputSampleRate,
                                               channels: 1, interleaved: false) else { throw AudioError.converterUnavailable }
        lock.lock(); playbackFormat = outputFormat; lock.unlock()
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        try installInputTap()
        engine.prepare()
        do { try engine.start() }
        catch { throw AudioError.engineStartFailed(String(describing: error)) }
        player.play()
        lock.lock(); running = true; lock.unlock()
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                          queue: nil) { [weak self] _ in self?.renegotiate() }
    }

    public func stop() {
        lock.lock(); let wasRunning = running; running = false; lock.unlock()
        guard wasRunning else { return }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        player.stop(); player.reset()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func installInputTap() throws {
        let input = engine.inputNode
        let hardwareFormat = input.inputFormat(forBus: 0)   // actual rate AFTER enabling VP (errata B9)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else { throw AudioError.noInputDevice }
        guard let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: configuration.wireSampleRate,
                                             channels: 1, interleaved: true),
              let newConverter = AVAudioConverter(from: hardwareFormat, to: wireFormat) else {
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
        let ratio = buffer.format.sampleRate / configuration.wireSampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) / ratio).rounded(.up) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var consumedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, statusPointer in
            if consumedInput { statusPointer.pointee = .noDataNow; return nil }
            consumedInput = true; statusPointer.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status == .haveData || status == .inputRanDry,
              let channel = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
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
        lock.unlock()
        if engine.isRunning, !player.isPlaying { player.play() }
    }

    /// The kill-switch/barge-in panic path. Synchronous — the caller measures T7 from this
    /// return. Playback stays stopped until `beginPlaybackTurn()`.
    public func stopPlaybackNow() {
        lock.lock()
        playbackSuppressed = true; playbackPrimed = false; playbackBuffered.removeAll()
        playbackOutstanding = 0; playbackStartedAt = nil
        lock.unlock()
        if player.engine != nil {
            player.stop(); player.reset()
            if engine.isRunning { player.play() }
        }
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
            self?.playbackCompleted()
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
        guard conversionError == nil, status == .haveData || status == .inputRanDry, output.frameLength > 0 else { return nil }
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
            self.lock.lock()
            let wasRunning = self.running
            self.playbackPrimed = false; self.playbackBuffered.removeAll()
            self.playbackPartial.removeAll(keepingCapacity: true)
            self.playbackOutstanding = 0; self.playbackStartedAt = nil
            self.lock.unlock()
            guard wasRunning else { return }
            self.log.notice("AVAudioEngineConfigurationChange — re-negotiating formats")
            self.engine.stop()
            if self.tapInstalled { self.engine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
            do {
                try self.installInputTap()
                try self.engine.start()
                self.player.play()
                self.onDeviceChange?(DeviceChange(
                    inputSampleRate: self.engine.inputNode.inputFormat(forBus: 0).sampleRate,
                    outputSampleRate: self.engine.outputNode.outputFormat(forBus: 0).sampleRate))
                self.log.notice("audio engine restarted after device change")
            } catch {
                self.lock.lock(); self.running = false; self.lock.unlock()
                self.onError?(.engineStartFailed(String(describing: error)))
                self.log.error("audio engine could not restart after device change: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
