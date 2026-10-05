import AVFoundation
import Foundation

/// Live microphone capture for the Chunk 5.5 English conversation slice:
/// VoiceProcessingIO (AEC) → 16 kHz mono Int16 → exact 20 ms frames.
/// Device-bound; ordering and callback timing are verified by the Task 5.5.4
/// manual OS checks.
public final class MicrophoneCapture: @unchecked Sendable {
    public enum CaptureError: Error, Equatable {
        case noInputDevice
        case converterUnavailable
        case engineStartFailed(String)
    }

    /// Called on the tap thread with exactly `PCMChunks.defaultFrameSampleCount`
    /// (320-sample, 20 ms) frames.
    public var onFrame: (@Sendable ([Int16]) -> Void)?
    /// Called with a human-readable message when capture cannot proceed.
    public var onError: (@Sendable (String) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false
    private var feeder = PCMChunks.FrameFeeder()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    public init() {}

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }

        // Enable voice processing while the engine is stopped, then read the
        // resulting hardware format (spec §4.1 ordering).
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)

        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw CaptureError.converterUnavailable
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw CaptureError.converterUnavailable
        }

        self.converter = converter
        self.targetFormat = targetFormat
        let ratio = 16_000 / hardwareFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = self.converter, let targetFormat = self.targetFormat else { return }

            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                self.onError?("Live microphone: failed to allocate conversion buffer.")
                return
            }

            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error else {
                self.onError?("Live microphone: audio conversion failed (\(conversionError?.localizedDescription ?? "unknown error")).")
                return
            }
            guard let channel = output.int16ChannelData?[0] else { return }

            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            self.lock.lock()
            let frames = self.feeder.feed(samples)
            self.lock.unlock()
            guard let onFrame = self.onFrame else { return }
            for frame in frames { onFrame(frame) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
        running = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feeder = PCMChunks.FrameFeeder()
    }
}
