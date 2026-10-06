import ClickyCore
import XCTest
@testable import ClickyOverlay

/// Companion activity → visual mapping (Task T-OVERLAY): deterministic like the
/// ghost-cursor styles — the model never picks color or motion, and every
/// visible activity has exactly one motion cue.
final class CompanionVisualStyleTests: XCTestCase {
    func testHiddenIsInvisibleWithNoMotionCue() {
        let style = CompanionVisualStyle.style(for: .hidden)
        XCTAssertFalse(style.isVisible)
        XCTAssertFalse(style.showsWaveform)
        XCTAssertFalse(style.showsSpinner)
        XCTAssertFalse(style.pulsesRing)
    }

    func testActivityVisualMapping() {
        let listening = CompanionVisualStyle.style(for: .listening)
        XCTAssertTrue(listening.isVisible)
        XCTAssertEqual(listening.tint, .aiBlue)
        XCTAssertTrue(listening.showsWaveform)

        let thinking = CompanionVisualStyle.style(for: .thinking)
        XCTAssertTrue(thinking.isVisible)
        XCTAssertEqual(thinking.tint, .reviewAmber)
        XCTAssertTrue(thinking.showsSpinner)

        let speaking = CompanionVisualStyle.style(for: .speaking)
        XCTAssertTrue(speaking.isVisible)
        XCTAssertEqual(speaking.tint, .stoppedGreen)
        XCTAssertTrue(speaking.pulsesRing)
    }

    func testEveryVisibleActivityHasExactlyOneMotionCue() {
        for activity in CompanionActivity.allCases where activity != .hidden {
            let style = CompanionVisualStyle.style(for: activity)
            let cues = [style.showsWaveform, style.showsSpinner, style.pulsesRing].filter { $0 }.count
            XCTAssertEqual(cues, 1, "\(activity) must have exactly one motion cue")
        }
    }
}

/// Timer-lifecycle policy: the mouse-follow loop runs for every visible
/// activity and stops completely (power) on `.hidden`.
final class CompanionTrackingPolicyTests: XCTestCase {
    func testStartsHiddenAndStopsTracking() {
        let policy = CompanionTrackingPolicy()
        XCTAssertEqual(policy.activity, .hidden)
        XCTAssertFalse(policy.isTracking)
    }

    func testTrackingRunsForEveryVisibleActivityAndStopsOnHidden() {
        var policy = CompanionTrackingPolicy()
        XCTAssertTrue(policy.apply(.listening))
        XCTAssertTrue(policy.isTracking)
        XCTAssertTrue(policy.apply(.thinking))
        XCTAssertTrue(policy.apply(.speaking))
        XCTAssertFalse(policy.apply(.hidden))
        XCTAssertFalse(policy.isTracking)
        XCTAssertTrue(policy.apply(.listening))   // restarts after a stop
    }
}

/// Mouse → screen → panel-local resolution for the companion, pinned in both
/// coordinate systems (spec §4.3, errata B2 is the AX timeout item — the
/// convention itself is §4.3).
final class CompanionTrackingGeometryTests: XCTestCase {
    private let screens = [
        DisplayGeometry(id: 1, cgFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                        appKitFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scaleFactor: 1),
        DisplayGeometry(id: 2, cgFrame: CGRect(x: -1280, y: 56, width: 1280, height: 1024),
                        appKitFrame: CGRect(x: -1280, y: 0, width: 1280, height: 1024), scaleFactor: 1),
    ]

    func testMouseOnPrimaryScreenConvertsToLocalTopLeftPoint() {
        // AppKit bottom-left y-up: y=100 from the bottom of a 1080-tall primary
        // is CG y=980 from the top.
        let resolved = CompanionTracking.localPoint(appKitMouseLocation: CGPoint(x: 500, y: 100),
                                                    primaryHeight: 1080,
                                                    screens: screens)
        XCTAssertEqual(resolved?.screenID, 1)
        XCTAssertEqual(resolved?.point, CGPoint(x: 500, y: 980))
    }

    func testMouseOnSecondaryScreenResolvesThatScreensLocalPoint() {
        // Secondary CG frame starts at x=-1280, y=56; its AppKit frame starts
        // at y=0 with height 1024 (below the primary's menu-bar region).
        let resolved = CompanionTracking.localPoint(appKitMouseLocation: CGPoint(x: -640, y: 500),
                                                    primaryHeight: 1080,
                                                    screens: screens)
        XCTAssertEqual(resolved?.screenID, 2)
        XCTAssertEqual(resolved?.point, CGPoint(x: 640, y: 524))
    }

    func testMouseOffEveryScreenResolvesNothing() {
        // 3000 pt below the primary bottom: CG y = 1080 + 3000, outside every frame.
        XCTAssertNil(CompanionTracking.localPoint(appKitMouseLocation: CGPoint(x: 500, y: -3000),
                                                  primaryHeight: 1080,
                                                  screens: screens))
    }
}

/// Companion anchor placement: offset from the pointer tip, clamped inside the
/// panel.
final class CompanionLayoutTests: XCTestCase {
    private let panel = CGSize(width: 1920, height: 1080)

    func testCompanionOffsetsDownRightOfTheCursorTip() {
        let center = OverlayLayout.companionCenter(near: CGPoint(x: 500, y: 400), in: panel)
        XCTAssertEqual(center, CGPoint(x: 500 + OverlayLayout.companionOffset.x,
                                       y: 400 + OverlayLayout.companionOffset.y))
    }

    func testCompanionClampsInsideThePanel() {
        let bottomRight = OverlayLayout.companionCenter(near: CGPoint(x: 1918, y: 1078), in: panel)
        XCTAssertEqual(bottomRight.x, 1920 - OverlayLayout.margin)
        XCTAssertEqual(bottomRight.y, 1080 - OverlayLayout.margin)

        let topLeft = OverlayLayout.companionCenter(near: CGPoint(x: -50, y: -50), in: panel)
        XCTAssertEqual(topLeft.x, OverlayLayout.margin)
        XCTAssertEqual(topLeft.y, OverlayLayout.margin)
    }
}

/// Card panel placement: panel-local center → global CG → AppKit global, plus
/// the window-size contract (card + margin on every side).
final class OverlayCardPanelGeometryTests: XCTestCase {
    func testGlobalFrameCentersPanelOnTheLocalPoint() {
        let screen = CGRect(x: -1280, y: 56, width: 1280, height: 1024)
        let frame = OverlayGeometry.globalFrame(centeredAtLocalPoint: CGPoint(x: 640, y: 300),
                                                size: CGSize(width: 364, height: 128),
                                                onScreen: screen)
        XCTAssertEqual(frame, CGRect(x: -1280 + 640 - 182, y: 56 + 300 - 64, width: 364, height: 128))
    }

    func testAppKitFrameFlipsAgainstPrimaryHeight() {
        // CG top-left y=100, height 128, primary 1080 → AppKit origin y=852.
        let cg = CGRect(x: 40, y: 100, width: 364, height: 128)
        XCTAssertEqual(OverlayGeometry.appKitFrame(fromCGGlobal: cg, primaryHeight: 1080),
                       CGRect(x: 40, y: 852, width: 364, height: 128))
    }

    func testCardPanelIsTheCardPlusMargin() {
        XCTAssertEqual(OverlayLayout.cardPanelSize,
                       CGSize(width: OverlayLayout.cardSize.width + 2 * OverlayLayout.margin,
                              height: OverlayLayout.cardSize.height + 2 * OverlayLayout.margin))
    }

    func testCardPanelGrowsForAMeasuredTallerCard() {
        // The nominal card stays at the nominal panel size…
        XCTAssertEqual(OverlayLayout.cardPanelSize(fittingCard: OverlayLayout.cardSize),
                       OverlayLayout.cardPanelSize)
        // …while a longer prompt grows the panel (never shrinks it).
        let taller = OverlayLayout.cardPanelSize(fittingCard: CGSize(width: 340, height: 130))
        XCTAssertEqual(taller.width, OverlayLayout.cardPanelSize.width)
        XCTAssertEqual(taller.height, 130 + 2 * OverlayLayout.margin)
        let wider = OverlayLayout.cardPanelSize(fittingCard: CGSize(width: 400, height: 104))
        XCTAssertEqual(wider.width, 400 + 2 * OverlayLayout.margin)
    }
}

/// Notification contract for the companion: both object shapes are accepted,
/// and the session-state fallback maps as specified.
final class CompanionActivityNotificationTests: XCTestCase {
    func testActivityNotificationNameContract() {
        XCTAssertEqual(Notification.Name.clickyModelActivityChanged.rawValue, "clickyModelActivityChanged")
    }

    func testAcceptsActivityObjectAndRawValueString() {
        XCTAssertEqual(OverlayWindowController.companionActivity(from: CompanionActivity.speaking), .speaking)
        XCTAssertEqual(OverlayWindowController.companionActivity(from: "thinking"), .thinking)
        XCTAssertEqual(OverlayWindowController.companionActivity(from: "hidden"), .hidden)
        XCTAssertNil(OverlayWindowController.companionActivity(from: "dancing"))
        XCTAssertNil(OverlayWindowController.companionActivity(from: nil))
        XCTAssertNil(OverlayWindowController.companionActivity(from: 42))
    }

    func testSessionStateFallbackMapping() {
        XCTAssertEqual(OverlayWindowController.companionActivity(for: .listening), .listening)
        XCTAssertEqual(OverlayWindowController.companionActivity(for: .idle), .hidden)
        XCTAssertEqual(OverlayWindowController.companionActivity(for: .stopped(reason: .killSwitch)), .hidden)
        XCTAssertNil(OverlayWindowController.companionActivity(for: .reconnecting(reason: "network")))
        XCTAssertNil(OverlayWindowController.companionActivity(for: nil))
    }
}
