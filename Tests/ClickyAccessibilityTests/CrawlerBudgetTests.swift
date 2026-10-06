import XCTest
@testable import ClickyAccessibility
final class CrawlerBudgetTests: XCTestCase {
    func testCaps() {
        // Depth 12 is the user-approved fix (2026-10-06) over the spec's depth-5
        // cap: Chromium/Electron place AXWebArea at depth 7, so depth 5 saw zero
        // web elements. The node cap is unchanged.
        XCTAssertTrue(CrawlerBudget.allows(depth: 12, visitedNodes: 1999))
        XCTAssertFalse(CrawlerBudget.allows(depth: 13, visitedNodes: 10))
        XCTAssertFalse(CrawlerBudget.allows(depth: 1, visitedNodes: 2000))
        XCTAssertEqual(CrawlerBudget.interfaceTimeoutSeconds, 0.25)
        XCTAssertEqual(CrawlerBudget.maxDepth, 12)
        XCTAssertEqual(CrawlerBudget.maxNodes, 2000)
    }
}
