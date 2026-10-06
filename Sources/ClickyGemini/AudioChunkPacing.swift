import Foundation
/// Wire constants (spec §4.1, errata A3): audio/video go as single blobs in
/// `realtimeInput.audio` / `.video`, one per 20–40 ms. 100 ms is the tolerated
/// ceiling, never the target.
public enum AudioChunkPacing {
    public static let wireInputSampleRate = 16_000
    public static let wireOutputSampleRate = 24_000
    public static let exhaustiveChunkCeilingMs = 100
    public static let audioMimeType = "audio/pcm;rate=16000"
    public static let videoMimeType = "image/jpeg"
    public static func frameCount(sampleRate: Int, durationMs: Int) -> Int { sampleRate * durationMs / 1000 }
}
