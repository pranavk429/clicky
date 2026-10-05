import XCTest
@testable import ClickyCore
final class CoordinateMathTests: XCTestCase {
    private let primaryHeight: CGFloat = 1080
    func testPointAndFrameFlips() {
        let cg = CGPoint(x: 100, y: 200)
        XCTAssertEqual(CoordinateMath.appKitPoint(fromCG: cg, primaryHeight: primaryHeight), CGPoint(x: 100, y: 880))
        XCTAssertEqual(CoordinateMath.cgPoint(fromAppKit: CGPoint(x: 100, y: 880), primaryHeight: primaryHeight), cg)
        // Display left of a 1080-tall primary: AppKit {−1280,0,1280,1024} → CG y = 1080 − 1024 = 56.
        let ak = CGRect(x: -1280, y: 0, width: 1280, height: 1024)
        XCTAssertEqual(CoordinateMath.cgFrame(fromAppKit: ak, primaryHeight: primaryHeight),
                       CGRect(x: -1280, y: 56, width: 1280, height: 1024))
    }
    func testNormalizedVisionPointAndRetina() {
        let retina = DisplayGeometry(id: 1, cgFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     appKitFrame: CGRect(x: 0, y: 180, width: 1440, height: 900), scaleFactor: 2)
        XCTAssertEqual(retina.pixelSize, CGSize(width: 2880, height: 1800))
        XCTAssertEqual(CoordinateMath.cgPoint(fromNormalized: CGPoint(x: 0.5, y: 0.5), on: retina), CGPoint(x: 720, y: 450))
        XCTAssertEqual(CoordinateMath.cgPoint(fromNormalized: CGPoint(x: 1.4, y: -0.2), on: retina), CGPoint(x: 1440, y: 0))
    }
    func testDisplayLookupAndNormalizedInverse() {
        let displays = [
            DisplayGeometry(id: 1, cgFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), appKitFrame: .zero, scaleFactor: 1),
            DisplayGeometry(id: 2, cgFrame: CGRect(x: -1280, y: 56, width: 1280, height: 1024), appKitFrame: .zero, scaleFactor: 1),
        ]
        XCTAssertEqual(CoordinateMath.display(containing: CGPoint(x: -10, y: 500), in: displays)?.id, 2)
        XCTAssertNil(CoordinateMath.display(containing: CGPoint(x: 5000, y: 5000), in: displays))
        XCTAssertNil(CoordinateMath.normalizedPoint(fromCG: CGPoint(x: -2000, y: 10), on: displays[1]))
        XCTAssertEqual(CoordinateMath.normalizedPoint(fromCG: CGPoint(x: 960, y: 540), on: displays[0]), CGPoint(x: 0.5, y: 0.5))
    }
}
