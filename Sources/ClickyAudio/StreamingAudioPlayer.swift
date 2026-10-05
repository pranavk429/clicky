import AVFoundation
import Foundation

/// Streaming playback for the Chunk 5.5 English conversation slice: base64 PCM
/// chunks → 24 kHz mono Int16 → main mixer. Echo/barge-in policy lives in the
/// runner, not here. Device-bound; behavior is verified by the Task 5.5.4
/// manual OS checks.
@MainActor
public final class StreamingAudioPlayer {
    public enum PlayerError: Error, Equatable { case formatUnavailable }

    /// Called when the last scheduled buffer has finished playing.
    public var onDrained: (() -> Void)?

    /// At least one scheduled buffer outstanding.
    public var isPlaying: Bool { outstanding > 0 }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var outstanding = 0

    public init() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        ) else {
            throw PlayerError.formatUnavailable
        }
        self.format = format
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    public func start() throws {
        try engine.start()
        node.play()
    }

    public func enqueue(base64Chunks: [String]) {
        let samples = PCMChunks.samples(fromBase64Chunks: base64Chunks)
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.int16ChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        if !node.isPlaying { node.play() }
        outstanding += 1
        node.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in self?.bufferFinished() }
        }
    }

    public func stopAll() {
        outstanding = 0
        node.stop()
    }

    public func stop() {
        stopAll()
        engine.stop()
    }

    private func bufferFinished() {
        outstanding = max(0, outstanding - 1)
        if outstanding == 0 { onDrained?() }
    }
}
