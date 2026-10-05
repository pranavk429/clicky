import XCTest
@testable import ClickyAudio
final class AudioLevelTests: XCTestCase {
    func testRMSAndPeak() {
        XCTAssertEqual(AudioLevel.rms([0, 0, 0, 0]), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.rms([16384, -16384, 16384, -16384]), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.peak([100, -30000, 2000]), Float(30000) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.rms([]), 0)
        XCTAssertEqual(AudioLevel.peak([]), 0)
    }
}
