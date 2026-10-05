// Tests/ClickyAudioTests/AudioStreamEngineTests.swift
import XCTest
@testable import ClickyAudio

final class AudioStreamEngineTests: XCTestCase {
    func testJitterBufferStartsAtTwoChunks() {
        let policy = JitterBufferPolicy()
        XCTAssertEqual(policy.targetChunks, 2)
        XCTAssertEqual(policy.targetMillis, 40)
        XCTAssertFalse(policy.shouldStartPlayback(bufferedChunks: 1))
        XCTAssertTrue(policy.shouldStartPlayback(bufferedChunks: 2))
    }
    func testJitterBufferGrowsOnUnderrunAndClamps() {
        var policy = JitterBufferPolicy()
        policy.recordDelivery(hadUnderrun: true)
        XCTAssertEqual(policy.targetChunks, 3)
        for _ in 0..<10 { policy.recordDelivery(hadUnderrun: true) }
        XCTAssertEqual(policy.targetChunks, JitterBufferPolicy.maxChunks)
        XCTAssertEqual(policy.targetMillis, 100)
        XCTAssertEqual(policy.underrunCount, 11)
    }
    func testJitterBufferShrinksAfterCleanStreak() {
        var policy = JitterBufferPolicy()
        policy.recordDelivery(hadUnderrun: true)                  // 2 → 3 chunks
        for _ in 0..<(JitterBufferPolicy.cleanChunksToShrink - 1) { policy.recordDelivery(hadUnderrun: false) }
        XCTAssertEqual(policy.targetChunks, 3)
        policy.recordDelivery(hadUnderrun: false)                 // 100th clean chunk
        XCTAssertEqual(policy.targetChunks, 2)
    }
    func testAECMuteGateWindowAndThreshold() {
        let gate = AECMuteGate()
        XCTAssertTrue(gate.shouldMute(msSincePlaybackStart: 120, speakerLevel: 0.2))
        XCTAssertFalse(gate.shouldMute(msSincePlaybackStart: 350, speakerLevel: 0.2))
        XCTAssertFalse(gate.shouldMute(msSincePlaybackStart: 120, speakerLevel: 0.001))
        XCTAssertFalse(gate.shouldMute(msSincePlaybackStart: nil, speakerLevel: 0.2))
    }
    func testToneGeneratorLengthAndLevel() {
        let pcm = AudioToneGenerator.sinePCM(frequency: 440, durationSeconds: 0.02, sampleRate: 24_000, amplitude: 0.5)
        XCTAssertEqual(pcm.count, 480 * 2)
        var samples = [Int16](repeating: 0, count: pcm.count / 2)
        _ = samples.withUnsafeMutableBytes { pcm.copyBytes(to: $0) }
        XCTAssertEqual(AudioLevel.peak(samples), 0.5, accuracy: 0.01)
        XCTAssertEqual(AudioLevel.rms(samples), 0.3535, accuracy: 0.02)
    }
}
