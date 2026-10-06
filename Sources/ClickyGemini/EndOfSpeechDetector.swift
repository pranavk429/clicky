import ClickyAudio
import Foundation

/// Client half of the hybrid VAD (spec §4.1; Validation 01 §3.2): the server keeps
/// auto-VAD on, and once the client hears `silenceDurationMs` of contiguous silence
/// it sends `realtimeInput.audioStreamEnd`, bypassing the server's ≈800 ms default
/// end-of-turn wait.
///
/// The spec's client-side detector range is ~250–350 ms of silence; the spec's
/// ≈350–500 ms `silenceDurationMs` figure is the *server* auto-VAD guidance, not
/// this detector's range. The shipped 500 ms default is a deliberate live-tuning
/// decision above both: live testing chopped natural pauses in multi-clause
/// Hinglish at 300 ms. Tune live with `CLICKY_EOS_SILENCE_MS` (clamped to
/// 250–900 ms) — e.g. ~700 ms for long bilingual sentences — instead of rebuilding.
public struct EndOfSpeechDetector: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var silenceDurationMs: Int      // live-tuned; spec client range ~250–350 ms
        public var rmsThreshold: Float
        public var frameDurationMs: Int        // 20 ms frame from the audio engine

        public static let defaultSilenceDurationMs = 500
        /// Live-tuning envelope for `CLICKY_EOS_SILENCE_MS`: wide enough for
        /// ~700 ms Hinglish tuning, bounded so a bad value cannot disable the
        /// client detector or fire before any plausible pause.
        public static let silenceDurationRangeMs = 250...900

        public init(silenceDurationMs: Int = Configuration.defaultSilenceDurationMs,
                    rmsThreshold: Float = 0.02,
                    frameDurationMs: Int = 20) {
            self.silenceDurationMs = silenceDurationMs
            self.rmsThreshold = rmsThreshold
            self.frameDurationMs = frameDurationMs
        }

        /// `CLICKY_EOS_SILENCE_MS` parsed and clamped to `silenceDurationRangeMs`;
        /// missing, blank, or unparsable values keep the 500 ms default.
        public static func resolvedDefault(
            environment: [String: String] = ProcessInfo.processInfo.environment) -> Configuration {
            guard let raw = environment["CLICKY_EOS_SILENCE_MS"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, let value = Int(raw) else {
                return Configuration()
            }
            return Configuration(silenceDurationMs: min(max(value, silenceDurationRangeMs.lowerBound),
                                                        silenceDurationRangeMs.upperBound))
        }

        public static let clickyDefault = resolvedDefault()
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
