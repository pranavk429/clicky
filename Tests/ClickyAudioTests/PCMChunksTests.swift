// Tests/ClickyAudioTests/PCMChunksTests.swift
import XCTest
@testable import ClickyAudio

final class PCMChunksTests: XCTestCase {
    func testDecodesBase64ToLittleEndianSamples() {
        XCTAssertEqual(PCMChunks.samples(fromBase64: "AQD//w=="), [1, -1])   // 0x01 0x00 0xFF 0xFF
    }
    func testEncodesAndDecodesRoundTripPreservingExtremes() {
        let samples: [Int16] = [Int16.min, -2, 0, 2, Int16.max]
        let data = PCMChunks.littleEndianData(from: samples)
        XCTAssertEqual(data, Data([0x00, 0x80, 0xFE, 0xFF, 0x00, 0x00, 0x02, 0x00, 0xFF, 0x7F]))
        XCTAssertEqual(PCMChunks.samples(fromLittleEndianData: data), samples)
    }
    func testFlattensMultipleBase64ChunksInOrder() {
        XCTAssertEqual(PCMChunks.samples(fromBase64Chunks: ["AQAAAA==", "AgAAAA=="]), [1, 0, 2, 0])
    }
    func testMalformedOrOddInputReturnsEmptyInsteadOfCrashing() {
        XCTAssertEqual(PCMChunks.samples(fromBase64: "!!!"), [])
        XCTAssertEqual(PCMChunks.samples(fromLittleEndianData: Data([0x01])), [])
    }
    func testFrameFeederEmitsExactFramesAndHoldsRemainder() {
        var feeder = PCMChunks.FrameFeeder()
        let frames = feeder.feed([Int16](repeating: 7, count: 700))
        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames.allSatisfy { $0.count == 320 && $0.allSatisfy { $0 == 7 } })
        XCTAssertEqual(feeder.remainder.count, 60)
    }
    func testFrameFeederCarriesRemainderAcrossFeeds() {
        var feeder = PCMChunks.FrameFeeder()
        XCTAssertEqual(feeder.feed([Int16](repeating: 1, count: 200)).count, 0)
        let frames = feeder.feed([Int16](repeating: 2, count: 120))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0][199], 1)
        XCTAssertEqual(frames[0][200], 2)
        XCTAssertEqual(feeder.remainder.count, 0)
    }
}
