import CoreGraphics
import XCTest
@testable import ClickyGemini

/// Pins the user-approved `click_at` coordinate interpretation: fractions,
/// then 0..1000 normalized values, then raw frame pixels, with a final
/// fail-closed bounds check. The adapter (`ScreenLookingAdapter.mapFramePoint`)
/// runs this before its frame→screen geometry math.
final class FramePointInterpreterTests: XCTestCase {

    private func assertPoint(_ point: CGPoint?, _ x: CGFloat, _ y: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let point else { return XCTFail("expected a mapped point", file: file, line: line) }
        XCTAssertEqual(Double(point.x), Double(x), accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(Double(point.y), Double(y), accuracy: 0.001, file: file, line: line)
    }

    func testFractionsMapOntoTheFrame() {
        // 0.5/0.5 on 1280×800 → the exact center.
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 0.5, y: 0.5, width: 1280, height: 800), 640, 400)
        // The 0..1 corners are inclusive.
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 0, y: 0, width: 1280, height: 800), 0, 0)
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 1, y: 1, width: 1280, height: 800), 1280, 800)
    }

    func testNormalizedValuesScaleToTheFrame() {
        // 500/1000, 300/1000 on 1280×800 → (640, 240).
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 500, y: 300, width: 1280, height: 800), 640, 240)
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 1000, y: 1000, width: 1280, height: 800), 1280, 800)
    }

    func testRawPixelsAboveTheNormalizedRangeStayPixels() {
        // 1500/900 is above 1000, so it is raw frame pixels.
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 1500, y: 900, width: 2560, height: 1440), 1500, 900)
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 1001, y: 1001, width: 2560, height: 1440), 1001, 1001)
        // The raw-pixel top-right corner is inclusive, matching the old guard.
        assertPoint(FramePointInterpreter.interpretFrameCoordinates(x: 2560, y: 1440, width: 2560, height: 1440), 2560, 1440)
    }

    func testOutOfFrameAfterInterpretationFailsClosed() {
        // Raw pixels beyond the frame → nil (the pre-fix `no_frame` loop).
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 1500, y: 900, width: 1280, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 1281, y: 400, width: 1280, height: 800))
        // A mixed pair (one value above 1000) is raw on both axes, so the
        // in-range x does not save the out-of-frame y.
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 1000, y: 1500, width: 1280, height: 800))
    }

    func testUnusableValuesFailClosed() {
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: -1, y: 0.5, width: 1280, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 0.5, y: -1, width: 1280, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: .nan, y: 0.5, width: 1280, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 0.5, y: .infinity, width: 1280, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 0.5, y: 0.5, width: 0, height: 800))
        XCTAssertNil(FramePointInterpreter.interpretFrameCoordinates(x: 0.5, y: 0.5, width: 1280, height: 0))
    }
}
