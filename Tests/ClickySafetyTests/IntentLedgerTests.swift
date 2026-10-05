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
}
