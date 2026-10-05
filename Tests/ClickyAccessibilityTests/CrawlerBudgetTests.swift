import XCTest
@testable import ClickyAccessibility
final class CrawlerBudgetTests: XCTestCase {
    func testCaps() {
        XCTAssertTrue(CrawlerBudget.allows(depth: 5, visitedNodes: 1999))
        XCTAssertFalse(CrawlerBudget.allows(depth: 6, visitedNodes: 10))
        XCTAssertFalse(CrawlerBudget.allows(depth: 1, visitedNodes: 2000))
        XCTAssertEqual(CrawlerBudget.interfaceTimeoutSeconds, 0.25)
        XCTAssertEqual(CrawlerBudget.maxDepth, 5)
        XCTAssertEqual(CrawlerBudget.maxNodes, 2000)
    }
}
