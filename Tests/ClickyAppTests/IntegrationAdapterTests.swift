import ApplicationServices
import ClickyGemini
import ClickyInput
import CoreGraphics
import XCTest
@testable import ClickyApp
@testable import ClickyVision

// Task T-INTEGRATION helper tests that must live in the app-facing test target:
// `ScreenFrameSource` is in ClickyVision (no test target of its own) and
// `AXEngineAdapter` is internal to ClickyApp. Both helpers are pure seams, so
// these tests need no ScreenCaptureKit and no real hardware.

final class ScreenFrameSourceExclusionTests: XCTestCase {

    /// Errata B11: the display fallback excludes Clicky's own overlay panels by
    /// CGWindowID. Given all shareable window numbers [1, 2, 3] and requested
    /// exclusions [2], the filter's `excludingWindows:` selection is [2].
    func testWindowsToExcludeMatchesOnlyRequestedWindowNumbers() {
        XCTAssertEqual(ScreenFrameSource.windowsToExclude(windowNumbers: [1, 2, 3], excluding: [2]), [2])
        XCTAssertEqual(ScreenFrameSource.windowsToExclude(windowNumbers: [1, 2, 3], excluding: [4]), [],
                       "no match keeps the previous excludingWindows: [] behavior")
        XCTAssertEqual(ScreenFrameSource.windowsToExclude(windowNumbers: [1, 2, 3], excluding: []), [])
        XCTAssertEqual(ScreenFrameSource.windowsToExclude(windowNumbers: [], excluding: [1]), [])
        XCTAssertEqual(ScreenFrameSource.windowsToExclude(windowNumbers: [7, 7, 9], excluding: [7]), [7, 7],
                       "every matching window is excluded, duplicates included")
    }

    func testDefaultExclusionProviderExcludesNothing() async {
        let source = ScreenFrameSource()
        let ids = await source.excludedWindowNumbers()
        XCTAssertTrue(ids.isEmpty, "the default source must not exclude windows")
    }

    func testInjectedExclusionProviderIsUsed() async {
        let source = ScreenFrameSource(excludedWindowNumbers: { [42] })
        let ids = await source.excludedWindowNumbers()
        XCTAssertEqual(ids, [42])
    }
}

final class AXEngineAdapterActivationTests: XCTestCase {

    private static let target = ResolvedTarget(applicationName: "Notes", role: "AXButton", subrole: nil,
                                               title: "Project", windowTitle: "Notes",
                                               cgFrame: CGRect(x: 20, y: 40, width: 90, height: 24))

    private actor ActivationSpy {
        private(set) var requested: [String] = []
        private let result: Bool
        init(result: Bool) { self.result = result }
        func activate(_ name: String) -> Bool {
            requested.append(name)
            return result
        }
    }

    private struct InertElementServices: ElementServices {
        func performPress(on element: AXUIElement) -> AXError { .actionUnsupported }
        func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? { nil }
        func focusedElement() -> AXUIElement? { nil }
        func elementCenter(_ element: AXUIElement) -> CGPoint? { nil }
    }

    private final class InertEventPoster: EventPosting, @unchecked Sendable {
        private(set) var mouseTypes: [CGEventType] = []
        func postUnicode(_ text: String) {}
        func postKeyChord(keyCode: CGKeyCode, flags: CGEventFlags) {}
        func postMouse(type: CGEventType, at point: CGPoint) { mouseTypes.append(type) }
        func postScroll(delta: Int32, at point: CGPoint) {}
        func currentCursorLocation() -> CGPoint { .zero }
    }

    /// Click-through suppression: an element-targeted action whose app cannot be
    /// activated fails closed before any AX lookup or synthetic input — never
    /// into the wrong window.
    func testElementTargetedActionFailsClosedWhenTargetAppCannotBeActivated() async {
        let spy = ActivationSpy(result: false)
        let adapter = AXEngineAdapter(activateTargetApp: { name in await spy.activate(name) })
        let outcome = await adapter.perform(ResolvedAction(kind: .click, target: Self.target))
        XCTAssertEqual(outcome, .failed(reason: "target app could not be activated"))
        let requested = await spy.requested
        XCTAssertEqual(requested, ["Notes"], "the element's app is activated before any AX lookup")
    }

    /// Coordinate-anchored actions are exempt: frame validity already pins them
    /// to the captured frontmost app, so the activation gate must not run.
    func testCoordinateAnchoredActionDoesNotActivateTheTargetApp() async {
        let spy = ActivationSpy(result: false)
        let poster = InertEventPoster()
        let synthesizer = EventSynthesizer(
            poster: poster, elements: InertElementServices(),
            secureGuard: SecureInputGuard(elements: InertElementServices(), isSecureInputEnabled: { false }),
            pacing: .instant)
        let adapter = AXEngineAdapter(synthesizer: synthesizer,
                                      activateTargetApp: { name in await spy.activate(name) })
        let outcome = await adapter.perform(ResolvedAction(kind: .clickAt, target: Self.target,
                                                           point: CGPoint(x: 12, y: 34)))
        let requested = await spy.requested
        XCTAssertTrue(requested.isEmpty, "click_at never consults the activation gate")
        guard case .performed = outcome else { return XCTFail("the pointer click should still run, got \(outcome)") }
        XCTAssertEqual(poster.mouseTypes, [.mouseMoved, .leftMouseDown, .leftMouseUp])
    }
}
