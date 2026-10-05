import ApplicationServices
import XCTest
@testable import ClickyAccessibility

final class AXHotCacheTests: XCTestCase {
    private func makeCache(tree: FakeAXNode) -> (AXHotCache, FakeAXNodeFactory) {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = tree
        return (AXHotCache(crawler: AXTreeCrawler(source: factory)), factory)
    }
    func testCrawlAndLookupExcludeSecureFields() async {
        let (cache, _) = makeCache(tree: FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Notes"), children: [
            FakeAXNode(AXNodeAttributes(role: "AXButton", title: "Delete")),
            FakeAXNode(AXNodeAttributes(role: "AXTextField", subrole: "AXSecureTextField", title: "Search")),
        ]))
        await cache.activate(pid: ProcessInfo.processInfo.processIdentifier)
        await cache.crawlNow()
        let hit = await cache.lookup(ElementQuery(text: "delete", role: "AXButton"))
        XCTAssertEqual(hit?.snapshot.key.title, "delete")
        let secureHit = await cache.lookup(ElementQuery(text: "search", role: "AXTextField"))
        XCTAssertNil(secureHit)
    }
    func testStructureChangedDebouncesToASingleCrawl() async throws {
        let (cache, factory) = makeCache(tree: FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "W")))
        await cache.activate(pid: ProcessInfo.processInfo.processIdentifier)
        try await Task.sleep(nanoseconds: 200_000_000)     // let the activation crawl drain
        await cache.crawlNow()
        let baseline = factory.focusedWindowReadCount     // test-only counter; read between awaits
        for _ in 0..<25 { await cache.structureChanged() }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(factory.focusedWindowReadCount, baseline + 1)
    }
    func testRevalidatePassesWhenUnchangedAndFailsClosedWhenChanged() async {
        let node = FakeAXNode(AXNodeAttributes(role: "AXButton", title: "Save"))
        let factory = FakeAXNodeFactory()
        factory.probeNode = node
        let cache = AXHotCache(crawler: AXTreeCrawler(source: factory))
        let key = CacheKey(role: "AXButton", subrole: "", title: "Save", description: "")
        let stillThere = await cache.revalidate(key: key, against: node.element)
        XCTAssertTrue(stillThere)
        node.attrs.title = "Delete"                        // the UI changed between arm and execute
        let changed = await cache.revalidate(key: key, against: node.element)
        XCTAssertFalse(changed)
    }
}
