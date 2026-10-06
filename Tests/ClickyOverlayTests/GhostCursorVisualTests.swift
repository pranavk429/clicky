import XCTest
@testable import ClickyOverlay

/// The state → visual mapping is a safety artifact: the model never chooses
/// color or motion (spec §4.3). These tests pin every state's style.
final class OverlayVisualStyleTests: XCTestCase {
    func testStateToStyleMapping() {
        let moving = OverlayVisualStyle.style(for: .moving)
        XCTAssertEqual(moving.tint, .aiBlue)
        XCTAssertEqual(moving.boxLineWidth, 0)
        XCTAssertFalse(moving.pulses)

        let review = OverlayVisualStyle.style(for: .review)
        XCTAssertEqual(review.tint, .reviewAmber)
        XCTAssertGreaterThan(review.boxLineWidth, 0)
        XCTAssertFalse(review.pulses)

        let confirm = OverlayVisualStyle.style(for: .confirm)
        XCTAssertEqual(confirm.tint, .confirmRed)
        XCTAssertGreaterThan(confirm.boxLineWidth, review.boxLineWidth)
        XCTAssertTrue(confirm.pulses)
        XCTAssertTrue(confirm.restsOnTarget)

        let stopped = OverlayVisualStyle.style(for: .stopped)
        XCTAssertEqual(stopped.tint, .stoppedGreen)
        XCTAssertTrue(stopped.showsBanner)
        XCTAssertFalse(stopped.pulses)
    }

    func testEveryStateHasAVisibleStyle() {
        for state in OverlayVisualState.allCases {
            XCTAssertGreaterThan(OverlayVisualStyle.style(for: state).tint.alpha, 0)
        }
    }
}

final class PointerTrajectoryTests: XCTestCase {
    func testEasedProgressIsSymmetricSmoothstep() {
        XCTAssertEqual(PointerTrajectory.easedProgress(0), 0)
        XCTAssertEqual(PointerTrajectory.easedProgress(1), 1)
        XCTAssertEqual(PointerTrajectory.easedProgress(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PointerTrajectory.easedProgress(-1), 0)   // clamped
        XCTAssertEqual(PointerTrajectory.easedProgress(2), 1)    // clamped
        XCTAssertLessThan(PointerTrajectory.easedProgress(0.25), 0.25)
        XCTAssertGreaterThan(PointerTrajectory.easedProgress(0.75), 0.75)
    }

    func testQuadraticBezierPath() {
        let start = CGPoint(x: 0, y: 0)
        let control = CGPoint(x: 50, y: 100)
        let end = CGPoint(x: 100, y: 0)
        XCTAssertEqual(PointerTrajectory.position(start: start, control: control, end: end, progress: 0), start)
        XCTAssertEqual(PointerTrajectory.position(start: start, control: control, end: end, progress: 1), end)
        // B(0.5) = 0.25·start + 0.5·control + 0.25·end
        XCTAssertEqual(PointerTrajectory.position(start: start, control: control, end: end, progress: 0.5),
                       CGPoint(x: 50, y: 50))
    }

    func testControlPointArcsPerpendicularToTravel() {
        XCTAssertEqual(PointerTrajectory.controlPoint(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)),
                       CGPoint(x: 50, y: 24))
        XCTAssertEqual(PointerTrajectory.controlPoint(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 100)),
                       CGPoint(x: -24, y: 50))
        // Zero-length travel keeps the midpoint (no NaN).
        XCTAssertEqual(PointerTrajectory.controlPoint(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5)),
                       CGPoint(x: 5, y: 5))
    }
}

final class OverlayLayoutTests: XCTestCase {
    private let panel = CGSize(width: 1920, height: 1080)

    func testCardPrefersBelowTheTarget() {
        let center = OverlayLayout.cardCenter(near: CGRect(x: 100, y: 100, width: 200, height: 50), in: panel)
        XCTAssertEqual(center.x, 200)
        XCTAssertEqual(center.y, 214)  // 150 (rect maxY) + 12 margin + 52 (half card)
    }

    func testCardFlipsAboveNearTheBottomEdge() {
        let center = OverlayLayout.cardCenter(near: CGRect(x: 100, y: 1000, width: 200, height: 50), in: panel)
        XCTAssertEqual(center.y, 936)  // 1000 (rect minY) − 12 − 52
    }

    func testCardClampsAtTheRightEdge() {
        let center = OverlayLayout.cardCenter(near: CGRect(x: 1800, y: 100, width: 200, height: 50), in: panel)
        XCTAssertEqual(center.x, 1920 - 170 - 12)
    }

    func testBannerIsTopCentered() {
        XCTAssertEqual(OverlayLayout.bannerCenter(in: panel), CGPoint(x: 960, y: 44))
    }
}
