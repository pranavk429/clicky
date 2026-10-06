import AppKit
import ClickyCore
import ScreenCaptureKit
import XCTest
@testable import ClickyOverlay

/// Live checks: `CLICKY_OVERLAY_LIVE=1 swift test --filter OverlayLiveTests`
/// on a logged-in desktop session. `testLiveStateCycle` shows each state for a
/// few seconds so a human can run the Task 11.4 manual checks.
@MainActor
final class OverlayLiveTests: XCTestCase {
    private func requireLiveOverlay() throws -> OverlayWindowController {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLICKY_OVERLAY_LIVE"] == "1",
                          "set CLICKY_OVERLAY_LIVE=1 on a logged-in desktop session")
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        let controller = OverlayWindowController.shared
        controller.start()
        pause(0.3)   // let the panels reach the window server before reading IDs
        return controller
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testOnePanelPerScreenWithLiveWindowIDs() throws {
        let controller = try requireLiveOverlay()
        defer { controller.stop() }
        XCTAssertEqual(controller.panelWindowIDs.count, NSScreen.screens.count)
        XCTAssertTrue(controller.panelWindowIDs.allSatisfy { $0 != 0 }, "panels must be on screen to have CGWindowIDs")
    }

    func testLiveStateCycle() throws {
        let controller = try requireLiveOverlay()
        defer { controller.stop() }
        controller.onCardAction = { [weak controller] action in
            controller?.present(.stopped(reason: action == .confirm ? "card confirm" : "card cancel"))
        }
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY ?? 0
        let cgFrames = NSScreen.screens.map { CoordinateMath.cgFrame(fromAppKit: $0.frame, primaryHeight: primaryHeight) }
        let primary = cgFrames[0]
        controller.present(.moving(to: CGPoint(x: primary.midX, y: primary.midY)))
        pause(4)
        for frame in cgFrames {   // multi-display: one review box per screen in turn
            controller.present(.review(rect: CGRect(x: frame.midX - 120, y: frame.midY + 60, width: 240, height: 120),
                                       label: "Review — button target"))
            pause(4)
        }
        controller.present(.confirm(rect: CGRect(x: primary.midX - 120, y: primary.midY + 60, width: 240, height: 120),
                                    point: CGPoint(x: primary.midX, y: primary.midY + 120),
                                    prompt: "Delete note 'Project'. Say Haan to confirm, or Ruko to cancel."))
        pause(12)   // VoiceOver / Accessibility Inspector checks run in this window
        controller.present(.stopped(reason: "kill switch"))
        pause(5)
        controller.present(.hidden)
    }

    func testPanelsAreExcludedFromShareableContent() async throws {
        let controller = try requireLiveOverlay()
        defer { controller.stop() }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw XCTSkip("ScreenCaptureKit unavailable — grant Terminal Screen Recording, restart it, re-run: \(error)")
        }
        let overlayIDs = Set(controller.panelWindowIDs)
        let shareableIDs = Set(content.windows.map(\.windowID))
        XCTAssertTrue(overlayIDs.isDisjoint(with: shareableIDs),
                      "overlay panels must never be shareable: \(overlayIDs.intersection(shareableIDs))")
    }
}
