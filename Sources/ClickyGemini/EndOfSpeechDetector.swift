import ClickyAudio
import Foundation

/// Client half of the hybrid VAD (spec §4.1; Validation 01 §3.2): the server keeps
/// auto-VAD on, and once the client hears `silenceDurationMs` of contiguous silence
/// (default 300 ms; tuned range 250–350 ms) it sends `realtimeInput.audioStreamEnd`,
/// bypassing the server's ≈800 ms default end-of-turn wait. Raise the duration if
/// multi-clause Hinglish accuracy degrades.
public struct EndOfSpeechDetector: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var silenceDurationMs: Int      // 250–350 ms per spec §4.1
        public var rmsThreshold: Float
        public var frameDurationMs: Int        // 20 ms frame from the audio engine

        public init(silenceDurationMs: Int = 300, rmsThreshold: Float = 0.02, frameDurationMs: Int = 20) {
            self.silenceDurationMs = silenceDurationMs
            self.rmsThreshold = rmsThreshold
            self.frameDurationMs = frameDurationMs
        }

        public static let clickyDefault = Configuration()
    }

    public private(set) var configuration: Configuration
    private var silentMilliseconds = 0
    private var isInSpeech = false
    private var hasFiredForCurrentUtterance = false

    public init(configuration: Configuration = .clickyDefault) {
        self.configuration = configuration
    }

    /// Feed one frame of 16-bit PCM (20 ms @ 16 kHz = 320 samples). Returns `true`
    /// exactly once per speech burst: after a speech frame, when the configured
    /// silence duration has elapsed. Speech resets the counter; no repeat emission.
    public mutating func process(_ samples: [Int16]) -> Bool {
        if AudioLevel.rms(samples) >= configuration.rmsThreshold {
            silentMilliseconds = 0
            isInSpeech = true
            hasFiredForCurrentUtterance = false
            return false
        }
        guard isInSpeech, !hasFiredForCurrentUtterance else { return false }
        silentMilliseconds += configuration.frameDurationMs
        guard silentMilliseconds >= configuration.silenceDurationMs else { return false }
        hasFiredForCurrentUtterance = true
        isInSpeech = false
        return true
    }
}
