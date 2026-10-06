import AppKit
import XCTest
@testable import ClickyOverlay

/// Race guard (Task T-CLEANUP): observer callbacks enqueue main-actor work that
/// can run after `stop()`. A screen-parameter notification delivered just before
/// teardown must not rebuild the panels; deferred work is a no-op once stopped.
@MainActor
final class OverlayStopRaceTests: XCTestCase {
    func testScreenChangeQueuedBeforeStopDoesNotResurrectPanels() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no active displays — panel resurrection would be unobservable")
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        let controller = OverlayWindowController.shared
        controller.start()
        defer { controller.stop() }
        XCTAssertFalse(controller.panelWindowIDs.isEmpty, "panels must exist for the race to be observable")
        // Delivery is synchronous on the main thread: this enqueues the observer's
        // main-actor Task; `stop()` tears down before that Task can run.
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        controller.stop()
        XCTAssertTrue(controller.panelWindowIDs.isEmpty)
        try await Task.sleep(for: .milliseconds(50))   // let any enqueued Task run
        XCTAssertTrue(controller.panelWindowIDs.isEmpty,
                      "post-teardown observer work must not rebuild the panels")
    }
}
