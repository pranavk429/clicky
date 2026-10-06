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

    func testClickHoldsBetweenDownAndUpForAtLeast30Milliseconds() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let synthesizer = makeTestSynthesizer(poster: poster, elements: elements, pacing: .default)
        _ = await synthesizer.click(at: CGPoint(x: 120, y: 240))
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.mouseMoved, .leftMouseDown, .leftMouseUp])
        guard let down = poster.mouseEvents.first(where: { $0.type == .leftMouseDown }),
              let up = poster.mouseEvents.first(where: { $0.type == .leftMouseUp }) else {
            return XCTFail("down and up expected")
        }
        let gap = up.timestamp.timeIntervalSince(down.timestamp)
        XCTAssertGreaterThanOrEqual(gap, 0.030,
                                    "WebKit/Chrome/AppKit drop clicks whose down/up share a timestamp")
        XCTAssertLessThan(gap, 1.0, "the hold stays imperceptible")
    }

    func testCancelledClickStillPostsMouseUp() async throws {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let pacing = SynthesisPacing(clickHold: .seconds(5))
        let synthesizer = makeTestSynthesizer(poster: poster, elements: elements, pacing: pacing)
        let clickTask = Task { await synthesizer.click(at: CGPoint(x: 7, y: 8)) }
        var spins = 0
        while !poster.mouseEvents.contains(where: { $0.type == .leftMouseDown }) && spins < 1000 {
            try await Task.sleep(for: .milliseconds(2)); spins += 1
        }
        XCTAssertTrue(poster.mouseEvents.contains(where: { $0.type == .leftMouseDown }))
        clickTask.cancel()   // kill switch / barge-in mid-hold
        _ = await clickTask.value
        XCTAssertEqual(poster.mouseEvents.map { $0.type }, [.mouseMoved, .leftMouseDown, .leftMouseUp],
                       "the mouse-up is posted even when the click task is cancelled mid-hold")
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

    func testScrollMagnitudeUnits() async {
        let poster = RecordingEventPoster(), synth = makeTestSynthesizer(poster: poster, elements: FakeElementServices())
        _ = await synth.scroll("down 2", on: makeSentinelElement())
        XCTAssertEqual(poster.scrollEvents.last?.delta, -30)
        _ = await synth.scroll("up", on: makeSentinelElement())
        XCTAssertEqual(poster.scrollEvents.last?.delta, 15)
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

    func testPressKeyRefusesWhileSecureInputBlocks() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let pressed = await makeTestSynthesizer(poster: poster, elements: elements,
                                                secureInputEnabled: { true })
            .pressKey("return", on: makeSentinelElement())
        XCTAssertFalse(pressed)
        XCTAssertTrue(poster.chords.isEmpty)
    }

    func testPressKeyRefusesUnknownKeyNames() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let pressed = await makeTestSynthesizer(poster: poster, elements: elements)
            .pressKey("delete", on: makeSentinelElement())
        XCTAssertFalse(pressed)
        XCTAssertTrue(poster.chords.isEmpty)
    }

    func testClickWithoutResolvablePointRefusesInsteadOfClickingTopLeft() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        elements.pressResult = .actionUnsupported
        elements.elementCenterPoint = nil
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements)
            .click(element: makeSentinelElement())
        XCTAssertEqual(outcome, .noTargetPoint(triggering: .actionUnsupported))
        XCTAssertTrue(poster.mouseEvents.isEmpty)
    }

    func testCancelledDragDoesNotDisruptSubsequentDrag() async throws {
        let poster = RecordingEventPoster()
        let pacing = SynthesisPacing(verificationPollCount: 1, verificationPollInterval: .zero,
                                     dragSteps: 2, dragStepInterval: .milliseconds(500))
        let synthesizer = makeTestSynthesizer(poster: poster, elements: FakeElementServices(), pacing: pacing)
        let firstDrag = Task { await synthesizer.drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 0)) }
        var spins = 0
        while poster.mouseEvents.count < 2 && spins < 1000 {
            try await Task.sleep(for: .milliseconds(2)); spins += 1
        }
        XCTAssertEqual(poster.mouseEvents.count, 2)
        let released = await synthesizer.releaseHeldInput()
        XCTAssertTrue(released)
        let secondDrag = Task { await synthesizer.drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)) }
        await firstDrag.value
        await secondDrag.value
        XCTAssertEqual(poster.mouseEvents.map { $0.type },
                       [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                        .leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(poster.mouseEvents.last?.point, CGPoint(x: 100, y: 0))
    }
}
