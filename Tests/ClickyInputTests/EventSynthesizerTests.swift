import ApplicationServices
import CoreGraphics
import XCTest
@testable import ClickyInput

final class EventSynthesizerTests: XCTestCase {
    func testChunkedUnicodeTypingMatchesUnicodeChunker() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let text = "नमस्ते, सफारी उघड आणि पुण्याचे हवामान शोध."
        elements.focused = makeSentinelElement(); elements.valueReads = [nil, text]
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements).typeText(text)
        XCTAssertEqual(outcome, .directVerified)
        XCTAssertEqual(poster.unicodeChunks, UnicodeChunker.chunk(text))
        XCTAssertTrue(poster.unicodeChunks.allSatisfy { $0.utf16.count <= UnicodeChunker.maxUTF16UnitsPerEvent })
    }

    func testUnverifiedDirectEntryFallsBackToPasteboardAndRestoresClipboard() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices(), pasteboard = RecordingPasteboard()
        elements.focused = makeSentinelElement(); elements.valueReads = [nil, nil, "hello", "hello", "hellohello"]
        let synth = makeTestSynthesizer(poster: poster, elements: elements, pasteboard: pasteboard)
        let outcome = await synth.typeText("hello")
        XCTAssertEqual(outcome, .pasteboardVerified)
        XCTAssertEqual(pasteboard.written, ["hello"]); XCTAssertEqual(pasteboard.restored, ["old clipboard"])
        XCTAssertEqual(poster.chords.count, 1); XCTAssertEqual(poster.chords.first?.keyCode, 9)
        XCTAssertEqual(poster.chords.first?.flags, .maskCommand)
        let pasteDirect = await synth.typeText("hello", preferPaste: true)
        XCTAssertEqual(pasteDirect, .pasteboardVerified)
    }

    func testDoubleVerificationFailureRefuses() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices(), pasteboard = RecordingPasteboard()
        elements.focused = makeSentinelElement(); elements.valueReads = [nil, nil, nil]
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements, pasteboard: pasteboard).typeText("hello")
        guard case .unverified(let reason) = outcome else { return XCTFail("expected .unverified, got \(outcome)") }
        XCTAssertTrue(reason.contains("pasteboard fallback"))
        XCTAssertEqual(pasteboard.restored, ["old clipboard"])
    }

    func testEmptyTextIsRefusedWithoutAnyEvents() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices(), pasteboard = RecordingPasteboard()
        elements.focused = makeSentinelElement()
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements, pasteboard: pasteboard).typeText("")
        XCTAssertEqual(outcome, .unverified(reason: "refusing to enter empty text"))
        XCTAssertTrue(poster.unicodeChunks.isEmpty && poster.chords.isEmpty && pasteboard.written.isEmpty)
    }

    func testGlobalSecureInputBlocksBeforeAnyEvent() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices(), pasteboard = RecordingPasteboard()
        elements.focused = makeSentinelElement()
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements, pasteboard: pasteboard,
                                                secureInputEnabled: { true }).typeText("hello")
        XCTAssertEqual(outcome, .blocked(rule: .globalSecureEventInput))
        XCTAssertTrue(poster.unicodeChunks.isEmpty && poster.chords.isEmpty && pasteboard.written.isEmpty)
    }

    func testMidEntrySecureInputStopsAfterFirstChunk() async {
        final class CallCounter: @unchecked Sendable { var count = 0 }
        let counter = CallCounter(), poster = RecordingEventPoster(), elements = FakeElementServices()
        elements.focused = makeSentinelElement()
        let text = String(repeating: "a", count: 25)
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements, secureInputEnabled: {
            counter.count += 1; return counter.count > 2
        }).typeText(text)
        XCTAssertEqual(outcome, .blocked(rule: .globalSecureEventInput))
        XCTAssertEqual(poster.unicodeChunks, [String(repeating: "a", count: 20)])
    }

    func testMissingFocusedElementRefusesBeforeTyping() async {
        let poster = RecordingEventPoster(), elements = FakeElementServices()
        let outcome = await makeTestSynthesizer(poster: poster, elements: elements).typeText("hello")
        XCTAssertEqual(outcome, .unverified(reason: "no focused element to verify against"))
        XCTAssertTrue(poster.unicodeChunks.isEmpty)
    }

    // MARK: Key chords

    func testPressKeyCmdTPostsAnsiTWithCommandFlag() async {
        let poster = RecordingEventPoster()
        let pressed = await makeTestSynthesizer(poster: poster, elements: FakeElementServices())
            .pressKey("cmd+t", on: makeSentinelElement())
        XCTAssertTrue(pressed)
        XCTAssertEqual(poster.chords.count, 1)
        XCTAssertEqual(poster.chords.first?.keyCode, 17)   // ANSI 't'
        XCTAssertEqual(poster.chords.first?.flags, .maskCommand)
    }

    func testPressKeyCmdShiftTPostsAnsiTWithCommandAndShiftFlags() async {
        let poster = RecordingEventPoster()
        let pressed = await makeTestSynthesizer(poster: poster, elements: FakeElementServices())
            .pressKey("cmd+shift+t", on: makeSentinelElement())
        XCTAssertTrue(pressed)
        XCTAssertEqual(poster.chords.count, 1)
        XCTAssertEqual(poster.chords.first?.keyCode, 17)   // ANSI 't'
        XCTAssertEqual(poster.chords.first?.flags, [.maskCommand, .maskShift])
    }

    func testPressKeyPlainReturnStillPostsReturnKeyCode() async {
        let poster = RecordingEventPoster()
        let pressed = await makeTestSynthesizer(poster: poster, elements: FakeElementServices())
            .pressKey("return", on: makeSentinelElement())
        XCTAssertTrue(pressed)
        XCTAssertEqual(poster.chords.count, 1)
        XCTAssertEqual(poster.chords.first?.keyCode, 36)
        XCTAssertEqual(poster.chords.first?.flags, CGEventFlags())
    }

    func testPressKeyUnknownKeyReturnsFalseWithoutPosting() async {
        let poster = RecordingEventPoster()
        let pressed = await makeTestSynthesizer(poster: poster, elements: FakeElementServices())
            .pressKey("cmd+unknownkey", on: makeSentinelElement())
        XCTAssertFalse(pressed)
        XCTAssertTrue(poster.chords.isEmpty)
    }
}
