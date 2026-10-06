// Tests/ClickyAudioTests/AudioStreamEngineTests.swift
import XCTest
@testable import ClickyAudio

final class AudioStreamEngineTests: XCTestCase {
    func testWireChunkCadenceStaysAtTwentyMillis() {
        let configuration = AudioStreamEngine.Configuration()
        XCTAssertEqual(configuration.wireChunkFrames, 320)
        XCTAssertEqual(configuration.wireSampleRate, 16_000)
        XCTAssertEqual(configuration.wireChunkDurationMs, 20)
    }
    func testWireChunkDurationMsDerivesFromNonDefaultConfig() {
        var configuration = AudioStreamEngine.Configuration()
        configuration.wireChunkFrames = 480                            // 480 @ 16 kHz
        XCTAssertEqual(configuration.wireChunkDurationMs, 30)
        configuration.wireSampleRate = 0                               // bad config must not divide by zero
        XCTAssertEqual(configuration.wireChunkDurationMs, 0)
    }
    func testPlaybackSliceBytesMatchEightyFiveMillis() {
        XCTAssertEqual(AudioStreamEngine.playbackSliceBytes(sampleRate: 24_000), 4_080)   // 2040 samples
    }
    func testPlaybackSliceBytesRoundAtNonDefaultRate() {
        // 44.1 kHz * 85 ms = 3748.5 samples; round to 3749 (not truncate to 3748).
        XCTAssertEqual(AudioStreamEngine.playbackSliceBytes(sampleRate: 44_100), 7_498)
    }
    func testPlaybackSlicingEmitsWholeSliceAtExactBoundary() {
        let (slices, remainder) = AudioStreamEngine.slicePlaybackPCM(
            Data(repeating: 3, count: 2_040 * 2), sampleRate: 24_000)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].count, 2_040 * 2)
        XCTAssertTrue(remainder.isEmpty)
    }
    func testPlaybackSlicingEmitsWholeSlicesAndCarriesRemainder() {
        let (slices, remainder) = AudioStreamEngine.slicePlaybackPCM(
            Data(repeating: 7, count: 4_080 + 100), sampleRate: 24_000)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].count, 4_080)
        XCTAssertEqual(remainder.count, 100)
    }
    func testPlaybackSlicingEmitsMultipleSlicesInOrderPerFeed() {
        var data = Data(repeating: 1, count: 4_080)
        data.append(Data(repeating: 2, count: 4_080))
        data.append(Data(repeating: 3, count: 100))
        let (slices, remainder) = AudioStreamEngine.slicePlaybackPCM(data, sampleRate: 24_000)
        XCTAssertEqual(slices.count, 2, "one feed must emit every whole slice, not just the first")
        XCTAssertEqual(slices[0].first, 1)
        XCTAssertEqual(slices[0].last, 1)
        XCTAssertEqual(slices[1].first, 2)
        XCTAssertEqual(slices[1].last, 2)
        XCTAssertEqual(remainder.count, 100)
        XCTAssertEqual(remainder.first, 3)
    }
    func testPlaybackSlicingCarriesPartialRemainderAcrossFeeds() {
        let (firstSlices, firstRemainder) = AudioStreamEngine.slicePlaybackPCM(
            Data(repeating: 1, count: 4_000), sampleRate: 24_000)
        XCTAssertTrue(firstSlices.isEmpty)
        XCTAssertEqual(firstRemainder.count, 4_000)
        let (secondSlices, secondRemainder) = AudioStreamEngine.slicePlaybackPCM(
            firstRemainder + Data(repeating: 2, count: 80), sampleRate: 24_000)
        XCTAssertEqual(secondSlices.count, 1)
        XCTAssertEqual(secondSlices[0].count, 4_080)
        XCTAssertEqual(secondSlices[0].first, 1)
        XCTAssertEqual(secondSlices[0].last, 2)
        XCTAssertTrue(secondRemainder.isEmpty)
    }
    func testJitterBufferStartsAtOneSlice() {
        let policy = JitterBufferPolicy()
        XCTAssertEqual(policy.targetSlices, 1)
        XCTAssertEqual(policy.targetMillis, 85)
        XCTAssertFalse(policy.shouldStartPlayback(bufferedSlices: 0))
        XCTAssertTrue(policy.shouldStartPlayback(bufferedSlices: 1))
    }
    func testJitterBufferGrowsOnUnderrunAndClamps() {
        var policy = JitterBufferPolicy()
        policy.recordDelivery(hadUnderrun: true)                  // 1 → 2 slices (170 ms)
        XCTAssertEqual(policy.targetSlices, 2)
        XCTAssertEqual(policy.targetMillis, 170)
        policy.recordDelivery(hadUnderrun: true)                  // 2 → 3 slices (255 ms)
        XCTAssertEqual(policy.targetSlices, 3)
        XCTAssertEqual(policy.targetMillis, 255)
        for _ in 0..<10 { policy.recordDelivery(hadUnderrun: true) }
        XCTAssertEqual(policy.targetSlices, JitterBufferPolicy.maxSlices)
        XCTAssertEqual(policy.targetMillis, 255)
        XCTAssertEqual(policy.underrunCount, 12)
    }
    func testJitterBufferShrinksAfterCleanStreak() {
        var policy = JitterBufferPolicy()
        policy.recordDelivery(hadUnderrun: true)                  // 1 → 2 slices
        for _ in 0..<(JitterBufferPolicy.cleanSlicesToShrink - 1) { policy.recordDelivery(hadUnderrun: false) }
        XCTAssertEqual(policy.targetSlices, 2)
        policy.recordDelivery(hadUnderrun: false)                 // 20th clean slice
        XCTAssertEqual(policy.targetSlices, 1)
        XCTAssertEqual(policy.targetMillis, 85)
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
