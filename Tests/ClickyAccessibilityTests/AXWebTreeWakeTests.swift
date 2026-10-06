import ApplicationServices
import XCTest
@testable import ClickyAccessibility

/// Fake wake seam for policy tests: records calls and lets each test script the
/// family, the enable result, and the probe answer. `@unchecked Sendable` is
/// test-only — the crawler actor serializes calls and assertions run after awaits.
final class FakeWebTreeWaker: AXWebTreeWaking, @unchecked Sendable {
    var family: AXAppFamily = .native
    var enableSucceeds = true
    var waitResult = false
    var onWait: (() -> Void)?
    private(set) var detectCount = 0
    private(set) var enableCount = 0
    private(set) var waitCount = 0
    private(set) var restoreCount = 0

    func detectFamily(of pid: pid_t) -> AXAppFamily {
        detectCount += 1
        return family
    }
    func enableWebTreeIfNeeded(pid: pid_t, family: AXAppFamily) -> (() -> Void)? {
        enableCount += 1
        guard enableSucceeds else { return nil }
        return { self.restoreCount += 1 }
    }
    func waitForTreeWake(pid: pid_t) async -> Bool {
        waitCount += 1
        onWait?()
        return waitResult
    }
}

/// First-entry wake gate + re-crawl policy, verified with fakes (no AX IPC).
///
/// `[manual OS check]` — the real `SystemAXWebTreeWaker` path needs a live app:
/// 1. Adapter probe: open VS Code (or Chrome) with a window focused and run
///    `CLICKY_AX_LIVE=1 CLICKY_AX_PID=$(pgrep -x Code | head -1) swift test
///    --filter testLiveWebTreeAdapter`; expect `family=electron treeWake=true`.
/// 2. End-to-end: run the signed app, ask for screen context on a browser page,
///    and confirm links/buttons/videos appear in the crawl. The first crawl after
///    launch arms the wake; the tree builds asynchronously (~2.1 s measured for
///    Electron), so a second crawl must show the web content.
/// 3. Etiquette: after `AXAppAdapters.restoreAll()` (not wired to lifecycle yet),
///    the woken app's attribute is back to the pre-Clicky value.
/// 4. Comet (vendor-branded Chromium, `Comet Framework.framework`) is currently
///    detected as `.native` by the file-system heuristic and is therefore NOT
///    woken — pending the sign-off flagged in the plan's Chunk 6 erratum.
final class AXWebTreeWakeTests: XCTestCase {
    func testRegistryDetectsFamilyOnceAndGatesFirstEntry() {
        let registry = AXWebTreeWakeRegistry()
        var detections = 0
        let first = registry.familyAndFirstEntry(pid: 501) { _ in
            detections += 1
            return .electron
        }
        XCTAssertEqual(first.family, .electron)
        XCTAssertTrue(first.firstEntry)
        let second = registry.familyAndFirstEntry(pid: 501) { _ in
            detections += 1
            return .native
        }
        XCTAssertEqual(second.family, .electron)     // memoized: detect never re-runs
        XCTAssertFalse(second.firstEntry)
        XCTAssertEqual(detections, 1)
    }
    func testRegistryRestoreAllRunsEachClosureOnceAndClearsMemoization() {
        let registry = AXWebTreeWakeRegistry()
        var restores = 0
        registry.storeRestore(pid: 502, restore: { restores += 1 })
        registry.storeRestore(pid: 503, restore: nil)     // failed wake stores nothing
        registry.restoreAll()
        XCTAssertEqual(restores, 1)
        registry.restoreAll()
        XCTAssertEqual(restores, 1)                       // closures consumed
        let again = registry.familyAndFirstEntry(pid: 502) { _ in .chromium }
        XCTAssertTrue(again.firstEntry)                   // cleared → re-detect
        XCTAssertEqual(again.family, .chromium)
    }
    func testCrawlerRecrawlsOnceWhenFirstWakeProbeSucceeds() async {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Comet"))
        let waker = FakeWebTreeWaker()
        waker.family = .chromium
        waker.waitResult = true
        waker.onWait = {     // the web tree finishes building while the probe waits
            factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Comet"), children: [
                FakeAXNode(AXNodeAttributes(role: "AXWebArea", title: "Results")),
            ])
        }
        let crawler = AXTreeCrawler(source: factory, waker: waker, wakeRegistry: AXWebTreeWakeRegistry())
        let elements = await crawler.snapshot(focusedWindowOf: 601)
        XCTAssertTrue(elements.contains { $0.key.role == "axwebarea" })
        XCTAssertEqual(waker.enableCount, 1)
        XCTAssertEqual(waker.waitCount, 1)
        XCTAssertEqual(factory.focusedWindowReadCount, 2)   // first crawl + one re-crawl
    }
    func testCrawlerSkipsWakeForNativeAppsAndDoesNotRewakeWithinASession() async {
        let nativeFactory = FakeAXNodeFactory()
        nativeFactory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Notes"))
        let nativeWaker = FakeWebTreeWaker()
        let nativeCrawler = AXTreeCrawler(source: nativeFactory, waker: nativeWaker,
                                          wakeRegistry: AXWebTreeWakeRegistry())
        _ = await nativeCrawler.snapshot(focusedWindowOf: 602)
        XCTAssertEqual(nativeWaker.enableCount, 0)
        XCTAssertEqual(nativeWaker.waitCount, 0)
        XCTAssertEqual(nativeFactory.focusedWindowReadCount, 1)

        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Code"), children: [
            FakeAXNode(AXNodeAttributes(role: "AXWebArea", title: "Editor")),
        ])
        let waker = FakeWebTreeWaker()
        waker.family = .electron
        let crawler = AXTreeCrawler(source: factory, waker: waker, wakeRegistry: AXWebTreeWakeRegistry())
        _ = await crawler.snapshot(focusedWindowOf: 603)
        XCTAssertEqual(waker.enableCount, 1)
        XCTAssertEqual(waker.waitCount, 0)                  // already had a web area → no probe
        _ = await crawler.snapshot(focusedWindowOf: 603)
        XCTAssertEqual(waker.enableCount, 1)                // set at most once per app session
        XCTAssertEqual(waker.detectCount, 1)
        XCTAssertEqual(factory.focusedWindowReadCount, 2)   // one flatten per crawl, no re-crawl
    }
    func testCrawlerDoesNotRecrawlWhenEnableFailsOrProbeFails() async {
        let failedFactory = FakeAXNodeFactory()
        failedFactory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Comet"))
        let failedWaker = FakeWebTreeWaker()
        failedWaker.family = .chromium
        failedWaker.enableSucceeds = false
        let failedCrawler = AXTreeCrawler(source: failedFactory, waker: failedWaker,
                                          wakeRegistry: AXWebTreeWakeRegistry())
        _ = await failedCrawler.snapshot(focusedWindowOf: 604)
        XCTAssertEqual(failedWaker.enableCount, 1)
        XCTAssertEqual(failedWaker.waitCount, 0)            // nothing armed → no probe
        XCTAssertEqual(failedFactory.focusedWindowReadCount, 1)

        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Comet"))
        let waker = FakeWebTreeWaker()
        waker.family = .chromium
        waker.waitResult = false
        let crawler = AXTreeCrawler(source: factory, waker: waker, wakeRegistry: AXWebTreeWakeRegistry())
        let elements = await crawler.snapshot(focusedWindowOf: 605)
        XCTAssertEqual(waker.waitCount, 1)                  // one bounded probe
        XCTAssertEqual(factory.focusedWindowReadCount, 1)   // probe failed → no re-crawl
        XCTAssertEqual(elements.count, 1)                   // pre-wake flatten returned
    }
    func testCrawlerStoresRestoreClosureForRestoreAll() async {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Code"))
        let waker = FakeWebTreeWaker()
        waker.family = .electron
        let registry = AXWebTreeWakeRegistry()
        let crawler = AXTreeCrawler(source: factory, waker: waker, wakeRegistry: registry)
        _ = await crawler.snapshot(focusedWindowOf: 606)
        registry.restoreAll()
        XCTAssertEqual(waker.restoreCount, 1)
    }
    func testCrawlerKeepsFirstFlattenWhenTheRecrawlComesBackEmpty() async {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Comet"))
        let waker = FakeWebTreeWaker()
        waker.family = .chromium
        waker.waitResult = true
        waker.onWait = { factory.focusedWindowNode = nil }   // tree vanished mid-rebuild
        let crawler = AXTreeCrawler(source: factory, waker: waker, wakeRegistry: AXWebTreeWakeRegistry())
        let elements = await crawler.snapshot(focusedWindowOf: 607)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(factory.focusedWindowReadCount, 2)
    }
}
