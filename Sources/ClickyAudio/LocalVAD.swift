import Foundation

/// Barge-in detector (spec §4.4/§4.5; Validation 01 §2.3): pure energy state machine over
/// 20 ms frames. Onset is language-independent and fires in ~30–80 ms (tap ≤21 ms + 1–2
/// frames) — that is what makes the <150 ms local stop possible. The server `interrupted`
/// frame is confirmation, never the trigger.
public struct LocalVADConfiguration: Equatable, Sendable {
    public var onsetThreshold: Float      // RMS that starts a speech burst
    public var releaseThreshold: Float    // RMS below which a burst decays (hysteresis)
    public var onsetFrames: Int           // consecutive loud frames before onset fires
    public var releaseFrames: Int         // consecutive quiet frames before speech ends
    public init(onsetThreshold: Float = 0.03, releaseThreshold: Float = 0.015,
                onsetFrames: Int = 2, releaseFrames: Int = 15) {
        self.onsetThreshold = onsetThreshold
        self.releaseThreshold = releaseThreshold
        self.onsetFrames = onsetFrames
        self.releaseFrames = releaseFrames
    }
    public static let clickyDefault = LocalVADConfiguration()
}

public enum LocalVADEvent: Equatable, Sendable {
    case speechOnset(level: Float)        // T1 anchor
    case speechEnded(level: Float)
}

public struct LocalVAD: Sendable {
    public private(set) var configuration: LocalVADConfiguration
    public private(set) var isSpeechActive = false
    private var loudRun = 0
    private var quietRun = 0

    public init(configuration: LocalVADConfiguration = .clickyDefault) { self.configuration = configuration }

    /// Feed one 20 ms frame (320 samples @ 16 kHz) — reuses `AudioLevel.rms`.
    public mutating func process(samples: [Int16]) -> LocalVADEvent? { process(level: AudioLevel.rms(samples)) }

    public mutating func process(level: Float) -> LocalVADEvent? {
        if isSpeechActive {
            if level < configuration.releaseThreshold {
                quietRun += 1
                if quietRun >= configuration.releaseFrames {
                    isSpeechActive = false; quietRun = 0; loudRun = 0
                    return .speechEnded(level: level)
                }
            } else {
                quietRun = 0
            }
            return nil
        }
        guard level >= configuration.onsetThreshold else { loudRun = 0; return nil }
        loudRun += 1
        guard loudRun >= configuration.onsetFrames else { return nil }
        isSpeechActive = true; loudRun = 0; quietRun = 0
        return .speechOnset(level: level)
    }

    public mutating func reset() { isSpeechActive = false; loudRun = 0; quietRun = 0 }
}
