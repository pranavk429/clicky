import XCTest
@testable import ClickyGemini

final class EndOfSpeechDetectorTests: XCTestCase {
    private let config = EndOfSpeechDetector.Configuration(silenceDurationMs: 60, rmsThreshold: 0.02,
                                                           frameDurationMs: 20)
    private let speechFrame = [Int16](repeating: 12_000, count: 320)
    private let silenceFrame = [Int16](repeating: 0, count: 320)

    func testSilenceBeforeAnySpeechNeverFires() {
        var detector = EndOfSpeechDetector(configuration: config)
        for _ in 0..<10 { XCTAssertFalse(detector.process(silenceFrame)) }
    }

    func testSpeechThenEnoughSilenceFiresExactlyOnce() {
        var detector = EndOfSpeechDetector(configuration: config)
        XCTAssertFalse(detector.process(speechFrame))
        XCTAssertFalse(detector.process(silenceFrame))      // 20 ms
        XCTAssertFalse(detector.process(silenceFrame))      // 40 ms
        XCTAssertTrue(detector.process(silenceFrame))       // 60 ms -> fires
        XCTAssertFalse(detector.process(silenceFrame))      // no repeat until new speech
    }

    func testSpeechResetsTheSilenceCounter() {
        var detector = EndOfSpeechDetector(configuration: config)
        _ = detector.process(speechFrame)
        _ = detector.process(silenceFrame)
        _ = detector.process(silenceFrame)
        XCTAssertFalse(detector.process(speechFrame), "the speech frame resets the counter")
        XCTAssertFalse(detector.process(silenceFrame))
        XCTAssertFalse(detector.process(silenceFrame))
        XCTAssertTrue(detector.process(silenceFrame))
    }

    func testSecondUtteranceFiresAgain() {
        var detector = EndOfSpeechDetector(configuration: config)
        _ = detector.process(speechFrame)
        for _ in 0..<3 { _ = detector.process(silenceFrame) }   // fires on the 3rd
        XCTAssertFalse(detector.process(silenceFrame))
        XCTAssertFalse(detector.process(speechFrame))
        XCTAssertFalse(detector.process(silenceFrame))
        XCTAssertFalse(detector.process(silenceFrame))
        XCTAssertTrue(detector.process(silenceFrame))
    }

    func testQuietFramesBelowThresholdCountAsSilence() {
        var detector = EndOfSpeechDetector(
            configuration: .init(silenceDurationMs: 40, rmsThreshold: 0.1, frameDurationMs: 20))
        let loud = [Int16](repeating: 12_000, count: 320)       // rms ≈ 0.37 >= 0.1
        let quiet = [Int16](repeating: 1_000, count: 320)       // rms ≈ 0.03 < 0.1
        XCTAssertFalse(detector.process(loud))
        XCTAssertFalse(detector.process(quiet))
        XCTAssertTrue(detector.process(quiet))
    }

    func testClientSendsAudioStreamEndExactlyOncePerBurst() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let client = GeminiLiveClient(
            transportFactory: { transport },
            setupFactory: { _ in GeminiSetupBuilder.make(systemInstruction: "Test.") },
            vadConfiguration: EndOfSpeechDetector.Configuration(silenceDurationMs: 60,
                                                                rmsThreshold: 0.02, frameDurationMs: 20))
        try await client.start()
        try await client.sendAudioFrame(speechFrame)
        try await client.sendAudioFrame(silenceFrame)
        try await client.sendAudioFrame(silenceFrame)
        try await client.sendAudioFrame(silenceFrame)           // 3rd silent frame -> audioStreamEnd
        try await client.sendAudioFrame(silenceFrame)           // no second audioStreamEnd
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent.count, 1 + 5 + 1, "setup + 5 audio frames + one audioStreamEnd")
        XCTAssertEqual(sent.filter { $0 == #"{"realtimeInput":{"audioStreamEnd":true}}"# }.count, 1)
        await client.stop(reason: .userToggle)
    }
}
