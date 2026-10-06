import XCTest
@testable import ClickyApp

/// Pure-logic tests for the bounded pre-handshake mic buffer (the deaf-window
/// fix). The coordinator-level tests pin the flush ordering; these pin the
/// bound itself.
final class AudioFrameBufferTests: XCTestCase {
    func testDrainReturnsFramesOldestFirstAndEmptiesTheBuffer() {
        var buffer = AudioFrameBuffer(capacity: 4)
        buffer.append([1])
        buffer.append([2])
        buffer.append([3])

        XCTAssertEqual(buffer.drain(), [[1], [2], [3]])
        XCTAssertTrue(buffer.drain().isEmpty, "draining must empty the buffer")
    }

    func testOverflowDropsTheOldestFrames() {
        var buffer = AudioFrameBuffer(capacity: 3)
        for value in 1...5 { buffer.append([Int16(value)]) }

        XCTAssertEqual(buffer.frames.count, 3)
        XCTAssertEqual(buffer.drain(), [[3], [4], [5]],
                       "the newest frames survive; the oldest drop on overflow")
    }

    func testDefaultCapacityIsThreeSecondsOfTwentyMillisecondFrames() {
        XCTAssertEqual(AudioFrameBuffer.defaultCapacity, 150)
    }

    func testCapacityIsNeverZero() {
        var buffer = AudioFrameBuffer(capacity: 0)
        buffer.append([1])
        buffer.append([2])
        XCTAssertEqual(buffer.drain(), [[2]], "a zero capacity still keeps the newest frame")
    }
}
