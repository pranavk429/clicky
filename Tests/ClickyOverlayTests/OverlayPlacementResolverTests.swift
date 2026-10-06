import XCTest
import ClickyCore
@testable import ClickyOverlay

final class OverlayCommandTests: XCTestCase {
    func testCommandMappingCoversEveryState() {
        XCTAssertEqual(OverlayCommand.moving(to: .zero).visualState, .moving)
        XCTAssertEqual(OverlayCommand.review(rect: .zero, label: nil).visualState, .review)
        XCTAssertEqual(OverlayCommand.confirm(rect: .zero, point: .zero, prompt: "x").visualState, .confirm)
        XCTAssertEqual(OverlayCommand.stopped(reason: "x").visualState, .stopped)
        XCTAssertNil(OverlayCommand.hidden.visualState)
    }
}

/// Geometry is global CoreGraphics (top-left of primary, y down) on the way in,
/// panel-local (top-left, y down) on the way out (spec §4.3, errata B2).
final class OverlayPlacementResolverTests: XCTestCase {
    private let screens = [
        DisplayGeometry(id: 1, cgFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                        appKitFrame: .zero, scaleFactor: 1),
        DisplayGeometry(id: 2, cgFrame: CGRect(x: -1280, y: 56, width: 1280, height: 1024),
                        appKitFrame: .zero, scaleFactor: 1),
    ]

    func testMovingPointOnSecondScreen() {
        let result = OverlayPlacementResolver.resolve(.moving(to: CGPoint(x: -640, y: 512)),
                                                      screens: screens, lastActiveScreenID: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].screenID, 2)
        XCTAssertEqual(result[0].state, .moving)
        XCTAssertEqual(result[0].localPoint, CGPoint(x: 640, y: 456))
    }

    func testMovingPointOffScreenClampsToNearestScreen() {
        let result = OverlayPlacementResolver.resolve(.moving(to: CGPoint(x: -2000, y: 500)),
                                                      screens: screens, lastActiveScreenID: nil)
        XCTAssertEqual(result.first?.screenID, 2)
        XCTAssertEqual(result.first?.localPoint, CGPoint(x: 0, y: 444))
    }

    func testReviewRectConvertsAndClampsAndCarriesLabel() {
        let result = OverlayPlacementResolver.resolve(.review(rect: CGRect(x: -1400, y: 100, width: 400, height: 200),
                                                              label: "Switch tab"),
                                                      screens: screens, lastActiveScreenID: nil)
        XCTAssertEqual(result.first?.screenID, 2)
        XCTAssertEqual(result.first?.localRect, CGRect(x: 0, y: 44, width: 400, height: 200))
        XCTAssertEqual(result.first?.accessibilityText, "Switch tab")
    }

    func testConfirmCarriesPromptAndRestingPoint() {
        let command = OverlayCommand.confirm(rect: CGRect(x: 100, y: 100, width: 200, height: 50),
                                             point: CGPoint(x: 150, y: 120),
                                             prompt: "Delete note 'Project'")
        let result = OverlayPlacementResolver.resolve(command, screens: screens, lastActiveScreenID: nil)
        XCTAssertEqual(result.first?.screenID, 1)
        XCTAssertEqual(result.first?.state, .confirm)
        XCTAssertEqual(result.first?.localPoint, CGPoint(x: 150, y: 120))
        XCTAssertEqual(result.first?.localRect, CGRect(x: 100, y: 100, width: 200, height: 50))
        XCTAssertEqual(result.first?.accessibilityText, "Delete note 'Project'")
    }

    func testStoppedUsesLastActiveScreenThenFallsBackToPrimary() {
        let onSecond = OverlayPlacementResolver.resolve(.stopped(reason: "kill switch"),
                                                        screens: screens, lastActiveScreenID: 2)
        XCTAssertEqual(onSecond.first?.screenID, 2)
        XCTAssertEqual(onSecond.first?.accessibilityText, "Clicky stopped. kill switch")
        let stale = OverlayPlacementResolver.resolve(.stopped(reason: "timeout"),
                                                     screens: screens, lastActiveScreenID: 99)
        XCTAssertEqual(stale.first?.screenID, 1)
    }

    func testHiddenResolvesToNothing() {
        XCTAssertTrue(OverlayPlacementResolver.resolve(.hidden, screens: screens, lastActiveScreenID: 2).isEmpty)
    }
}
