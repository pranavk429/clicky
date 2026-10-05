import XCTest
@testable import ClickyGemini
final class AudioChunkPacingTests: XCTestCase {
    func testFrameMathAndMime() {
        XCTAssertEqual(AudioChunkPacing.frameCount(sampleRate: 16_000, durationMs: 20), 320)
        XCTAssertEqual(AudioChunkPacing.frameCount(sampleRate: 48_000, durationMs: 20), 960)
        XCTAssertEqual(AudioChunkPacing.audioMimeType, "audio/pcm;rate=16000")
        XCTAssertEqual(AudioChunkPacing.videoMimeType, "image/jpeg")
    }
}
