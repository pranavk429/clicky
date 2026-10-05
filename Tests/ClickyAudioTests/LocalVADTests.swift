// Tests/ClickyAudioTests/LocalVADTests.swift
import XCTest
@testable import ClickyAudio

final class LocalVADTests: XCTestCase {
    private let speech: Float = 0.2
    private let medium: Float = 0.02      // between releaseThreshold and onsetThreshold
    private let quiet: Float = 0.005

    func testQuietInputAndSingleSpikeNeverFire() {
        var vad = LocalVAD()
        for _ in 0..<50 { XCTAssertNil(vad.process(level: quiet)) }
        XCTAssertNil(vad.process(level: speech))       // one loud frame is not enough
        XCTAssertNil(vad.process(level: quiet))
        XCTAssertNil(vad.process(level: speech))
        XCTAssertFalse(vad.isSpeechActive)
    }
    func testOnsetRequiresTwoConsecutiveLoudFramesAndFiresOnce() {
        var vad = LocalVAD()
        XCTAssertNil(vad.process(level: speech))
        XCTAssertEqual(vad.process(level: speech), .speechOnset(level: speech))
        XCTAssertTrue(vad.isSpeechActive)
        XCTAssertNil(vad.process(level: speech), "onset fires once per burst")
    }
    func testHysteresisEndsOnlyAfterReleaseFramesThenSecondBurstFires() {
        var vad = LocalVAD()
        _ = vad.process(level: speech); _ = vad.process(level: speech)      // onset
        for _ in 0..<20 { XCTAssertNil(vad.process(level: medium)) }        // above releaseThreshold
        XCTAssertTrue(vad.isSpeechActive)
        for _ in 1..<15 { XCTAssertNil(vad.process(level: quiet)) }
        XCTAssertEqual(vad.process(level: quiet), .speechEnded(level: quiet))
        XCTAssertFalse(vad.isSpeechActive)
        XCTAssertNil(vad.process(level: speech))
        XCTAssertEqual(vad.process(level: speech), .speechOnset(level: speech))
    }
    func testResetClearsActiveSpeech() {
        var vad = LocalVAD()
        _ = vad.process(level: speech); _ = vad.process(level: speech)
        vad.reset()
        XCTAssertFalse(vad.isSpeechActive)
        XCTAssertNil(vad.process(level: speech))
        XCTAssertEqual(vad.process(level: speech), .speechOnset(level: speech))
    }
    func testProcessSamplesUsesAudioLevel() {
        var vad = LocalVAD()
        let loud = [Int16](repeating: 12_000, count: 320)   // RMS ≈ 0.366
        XCTAssertNil(vad.process(samples: loud))
        XCTAssertEqual(vad.process(samples: loud), .speechOnset(level: AudioLevel.rms(loud)))
    }
}
