import ApplicationServices
import CoreGraphics
import XCTest
@testable import ClickyInput

final class PointerSynthesisTests: XCTestCase {
    func testClickUsesAXPressWhenItSucceeds() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements)
            .click(element: makeSentinelElement(), fallbackPoint: CGPoint(x: 120, y: 240))
        XCTAssertEqual(outcome, .axPressed)
        XCTAssertEqual(elements.pressedElements.count, 1); XCTAssertTrue(poster.mouseEvents.isEmpty)
    }

    func testClickFallsBackToHoverThenClickWhenAXPressFails() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        elements.pressResult = .actionUnsupported
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements)
            .click(element: makeSentinelElement(), fallbackPoint: CGPoint(x: 120, y: 240))
        XCTAssertEqual(outcome, .clickFallback(triggering: .actionUnsupported))
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.mouseMoved, .leftMouseDown, .leftMouseUp])
        XCTAssertEqual(poster.mouseEvents.last?.point, CGPoint(x: 120, y: 240))
    }

    func testClickIsAllowedAndPostedWhileSecureInputIsEnabled() async {   // errata B8
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let decision = await makeTestSynthesizer(poster: poster, elements: elements,
                                                 secureInputEnabled: { true }).click(at: CGPoint(x: 5, y: 6))
        XCTAssertTrue(decision.allowed); XCTAssertEqual(decision.ruleFired, .globalSecureEventInput)
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.mouseMoved, .leftMouseDown, .leftMouseUp])
    }

    func testMoveMouseScrollAndPressKey() async {
        let poster = RecordingEventPoster(), synth = makeTestSynthesizer(poster: poster, elements: FakeElementServices())
        await synth.moveMouse(to: CGPoint(x: 7, y: 8))
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.mouseMoved])
        XCTAssertEqual(poster.mouseEvents.first?.point, CGPoint(x: 7, y: 8))
        let scrolled = await synth.scroll("down", on: makeSentinelElement())
        XCTAssertTrue(scrolled); XCTAssertEqual(poster.scrollEvents.count, 1)
        let pressed = await synth.pressKey("return", on: makeSentinelElement())
        XCTAssertTrue(pressed); XCTAssertEqual(poster.chords.count, 1)
    }

    func testDragPostsInterpolatedEvents() async {
        let poster = RecordingEventPoster()
        let synthesizer = makeTestSynthesizer(poster: poster, elements: FakeElementServices())
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 100, y: 50)
        await synthesizer.drag(from: start, to: end)
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(poster.mouseEvents.first?.point, start); XCTAssertEqual(poster.mouseEvents.last?.point, end)
        let releasedAfterCompletion = await synthesizer.releaseHeldInput()
        XCTAssertFalse(releasedAfterCompletion)
    }

    func testReleaseHeldInputIsNoOpWhenIdle() async {
        let synthesizer = makeTestSynthesizer(poster: RecordingEventPoster(), elements: FakeElementServices())
        let released = await synthesizer.releaseHeldInput()
        XCTAssertFalse(released)
    }

    func testReleaseHeldInputInterruptsActiveDrag() async throws {
        let poster = RecordingEventPoster()
        let pacing = SynthesisPacing(verificationPollCount: 1, verificationPollInterval: .zero,
                                     dragSteps: 2, dragStepInterval: .milliseconds(500))
        let synthesizer = makeTestSynthesizer(poster: poster, elements: FakeElementServices(), pacing: pacing)
        let dragTask = Task { await synthesizer.drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 0)) }
        var spins = 0
        while poster.mouseEvents.count < 2 && spins < 1000 {
            try await Task.sleep(for: .milliseconds(2)); spins += 1
        }
        XCTAssertEqual(poster.mouseEvents.count, 2)
        let released = await synthesizer.releaseHeldInput()
        XCTAssertTrue(released)
        await dragTask.value
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(poster.mouseEvents.last?.point, poster.cursorLocation)
    }
}
