import Foundation
/// Hard crawler budgets (spec §4.2/§4.5, errata B2/B3). The 0.25 s messaging
/// timeout is applied process-wide once via
/// `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)` —
/// per-element timeouts are NOT equivalent.
public enum CrawlerBudget {
    public static let interfaceTimeoutSeconds: Float = 0.25
    /// User-approved fix (2026-10-06) over the spec's depth-5 cap: measured
    /// Chromium/Electron trees place `AXWebArea` at depth 7 (VS Code 1.140.0 /
    /// Antigravity IDE), so depth 5 discovered zero web elements. The 2000-node
    /// cap still bounds crawl cost.
    public static let maxDepth = 12
    public static let maxNodes = 2000
    public static let debounceMilliseconds = 100
    public static func allows(depth: Int, visitedNodes: Int) -> Bool {
        depth <= maxDepth && visitedNodes < maxNodes
    }
}
