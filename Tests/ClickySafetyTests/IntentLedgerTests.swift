import XCTest
@testable import ClickySafety
final class IntentLedgerTests: XCTestCase {
    func testAuthorizesTraceableCalls() async {
        let ledger = IntentLedger()
        await ledger.record("delete my project notes")
        let decision = await ledger.authorize(.init(toolName: "execute_action", anchors: ["Delete"]))
        guard case .authorized = decision else { return XCTFail("expected authorized, got \(decision)") }
    }
    func testRefusesUntraceableCalls() async {
        let ledger = IntentLedger()
        await ledger.record("open the invoice and read it")          // T10: user asked to READ
        let poisoned = await ledger.authorize(.init(toolName: "execute_action", anchors: ["Terminal", "evil.com"]))
        XCTAssertEqual(poisoned, .refused(.noMatchingIntent))        // content-originated call: refused
        let fromScreenOnly = await ledger.authorize(.init(toolName: "open_url", anchors: ["https://evil.com/x?y=1"]))
        XCTAssertEqual(fromScreenOnly, .refused(.noMatchingIntent))
    }
    func testWindowExpiry() async {
        let clock = TestClock()
        let ledger = IntentLedger(windowSeconds: 120, now: { clock.now })
        await ledger.record("open safari")
        clock.advance(121)
        let expired = await ledger.authorize(.init(toolName: "execute_action", anchors: ["Safari"]))
        XCTAssertEqual(expired, .refused(.noMatchingIntent))
    }
    func testCapacityKeepsRecentIntents() async {
        let ledger = IntentLedger(capacity: 20)
        await ledger.record("first command about कोल्हापूर")
        for index in 0..<20 { await ledger.record("filler command number \(index)") }
        let oldest = await ledger.authorize(.init(toolName: "execute_action", anchors: ["कोल्हापूर"]))
        XCTAssertEqual(oldest, .refused(.noMatchingIntent))          // pruned by capacity
        let recent = await ledger.authorize(.init(toolName: "execute_action", anchors: ["filler"]))
        guard case .authorized = recent else { return XCTFail("newest intents must survive pruning") }
    }
    func testBlankEntriesAndAnchors() async {
        let ledger = IntentLedger()
        let blank = await ledger.record("   ")
        XCTAssertNil(blank)
        await ledger.record("open notes")
        let noAnchors = await ledger.authorize(.init(toolName: "execute_action", anchors: []))
        XCTAssertEqual(noAnchors, .refused(.noAnchors))
        let blankAnchor = await ledger.authorize(.init(toolName: "execute_action", anchors: [" "]))
        XCTAssertEqual(blankAnchor, .refused(.noAnchors))
    }
    func testTextCommandChannelAlsoAuthorizes() async {
        let ledger = IntentLedger()
        await ledger.record("trash the duplicate report", source: .textCommand)
        let decision = await ledger.authorize(.init(toolName: "execute_action", anchors: ["Trash"]))
        guard case .authorized = decision else { return XCTFail("text-command intents must authorize too") }
        let url = await ledger.authorize(.init(toolName: "open_url", anchors: ["https://en.wikipedia.org/wiki/Pune"]))
        XCTAssertEqual(url, .refused(.noMatchingIntent))             // domain never spoken: refused
    }
    func testParaphrasedIntentWithPartialOverlapAuthorizes() async {
        let ledger = IntentLedger()
        await ledger.record("delete my project notes")
        // Model paraphrase: synonym verb plus an extra noun; two of three
        // meaningful tokens (project, notes) still trace to the utterance.
        let paraphrase = await ledger.authorize(.init(toolName: "execute_action", anchors: ["remove project notes file"]))
        guard case .authorized = paraphrase else {
            return XCTFail("partial-overlap paraphrase must authorize, got \(paraphrase)")
        }
        // Plural/singular drift: "note" must match "notes".
        let plural = await ledger.authorize(.init(toolName: "execute_action", anchors: ["delete project note"]))
        guard case .authorized = plural else {
            return XCTFail("morphological variant must authorize, got \(plural)")
        }
        // Filler words in the paraphrase are ignored; the target still traces.
        await ledger.record("open settings")
        let filler = await ledger.authorize(.init(toolName: "execute_action", anchors: ["please open the settings page"]))
        guard case .authorized = filler else {
            return XCTFail("filler-only additions must authorize, got \(filler)")
        }
    }
    func testUnrelatedParaphraseStillRefused() async {
        let ledger = IntentLedger()
        await ledger.record("open the invoice and read it")
        // No meaningful token in common: screen-originated instruction.
        let unrelated = await ledger.authorize(.init(toolName: "execute_action", anchors: ["empty the recycle bin"]))
        XCTAssertEqual(unrelated, .refused(.noMatchingIntent))
        // Verb-only overlap: the user said "open", never "Terminal" (T10).
        let verbOnly = await ledger.authorize(.init(toolName: "execute_action", anchors: ["open Terminal"]))
        XCTAssertEqual(verbOnly, .refused(.noMatchingIntent))
        // Host with no spoken token: refused as before.
        let screenOnly = await ledger.authorize(.init(toolName: "execute_action", anchors: ["evil.com"]))
        XCTAssertEqual(screenOnly, .refused(.noMatchingIntent))
        // Weak-only anchors can never authorize by themselves.
        let weakOnly = await ledger.authorize(.init(toolName: "execute_action", anchors: ["please click"]))
        XCTAssertEqual(weakOnly, .refused(.noMatchingIntent))
    }
}
