import Foundation
/// RMS/peak over 16-bit linear PCM. Used by the end-of-speech detector
/// (Chunk 4) and the local barge-in VAD (Chunk 9), both on 20 ms frames.
public enum AudioLevel {
    public static func rms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for s in samples { let v = Double(s) / 32768.0; sum += v * v }
        return Float((sum / Double(samples.count)).squareRoot())
    }
    public static func peak(_ samples: [Int16]) -> Float {
        var maxAbs: Int16 = 0
        for s in samples {
            let magnitude = s == Int16.min ? Int16.max : abs(s)
            maxAbs = max(maxAbs, magnitude)
        }
        return Float(maxAbs) / 32768.0
    }
}
