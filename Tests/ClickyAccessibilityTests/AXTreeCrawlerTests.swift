import ApplicationServices
import XCTest
@testable import ClickyAccessibility

/// Fakes shared by every ClickyAccessibility test file in this target.
final class FakeAXNode: AXNode {
    let element = AXUIElementCreateSystemWide()
    var attrs: AXNodeAttributes
    private let kids: [FakeAXNode]

    init(_ attrs: AXNodeAttributes, children: [FakeAXNode] = []) {
        self.attrs = attrs
        self.kids = children
    }
    func children() -> [any AXNode] { kids }
    func attributes() -> AXNodeAttributes { attrs }
}

final class FakeAXNodeFactory: AXNodeFactory {
    var focusedWindowNode: FakeAXNode?
    var probeNode: FakeAXNode?
    private(set) var focusedWindowReadCount = 0

    func focusedWindow(of pid: pid_t) -> (any AXNode)? {
        focusedWindowReadCount += 1
        return focusedWindowNode
    }
    func node(for element: AXUIElement) -> any AXNode { probeNode ?? FakeAXNode(AXNodeAttributes()) }
}

final class AXTreeCrawlerTests: XCTestCase {
    func testGlobalMessagingTimeoutInstallsOnSystemWideElement() {
        // Errata B2: the 0.25 s guard must be process-wide, not per-element.
        XCTAssertEqual(AXTreeCrawler.installGlobalMessagingTimeout(), .success)
    }
    func testFlattenEnforcesBudgetCaps() async {
        var chain = FakeAXNode(AXNodeAttributes(role: "AXStaticText", title: "d13"))
        for depth in stride(from: 12, through: 0, by: -1) {
            chain = FakeAXNode(AXNodeAttributes(role: depth == 0 ? "AXWindow" : "AXGroup", title: "d\(depth)"),
                               children: [chain])
        }
        let depthFactory = FakeAXNodeFactory()
        depthFactory.focusedWindowNode = chain
        let chainElements = await AXTreeCrawler(source: depthFactory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(chainElements.count, 13)                   // depths 0...12
        XCTAssertEqual(chainElements.last?.key.title, "d12")

        let wideFactory = FakeAXNodeFactory()
        wideFactory.focusedWindowNode = FakeAXNode(
            AXNodeAttributes(role: "AXWindow", title: "List"),
            children: (0..<2_500).map { FakeAXNode(AXNodeAttributes(role: "AXStaticText", title: "row \($0)")) })
        let wideElements = await AXTreeCrawler(source: wideFactory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(wideElements.count, CrawlerBudget.maxNodes)     // 2000
    }
    func testFlattenDiscoversWebAreaBelowTheOldDepthFiveCap() async {
        // Regression (user-approved fix, 2026-10-06): Chromium/Electron place
        // AXWebArea at depth 7 (VS Code 1.140.0 / Antigravity IDE, measured), so
        // the old depth-5 cap discovered zero web content.
        var chain = FakeAXNode(AXNodeAttributes(role: "AXStaticText", title: "page content"))
        for depth in stride(from: 12, through: 0, by: -1) {
            chain = FakeAXNode(AXNodeAttributes(role: depth == 0 ? "AXWindow" : depth == 7 ? "AXWebArea" : "AXGroup",
                                                title: "d\(depth)"), children: [chain])
        }
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = chain
        let elements = await AXTreeCrawler(source: factory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(elements.count, CrawlerBudget.maxDepth + 1)     // depths 0...12
        XCTAssertTrue(elements.contains { $0.key.role == "axwebarea" && $0.key.title == "d7" })
    }
    func testSnapshotsCarryValuesAndRedactSecureFields() async {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Browser"), children: [
            FakeAXNode(AXNodeAttributes(role: "AXTextField", title: "Search", value: "clicky repo")),
            FakeAXNode(AXNodeAttributes(role: "AXTextField", subrole: "AXSecureTextField",
                                        title: "Password", value: "hunter2")),
            FakeAXNode(AXNodeAttributes(role: "AXTextField", title: "Notes",
                                        value: String(repeating: "x", count: 700))),
        ])
        let elements = await AXTreeCrawler(source: factory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(elements.first { $0.key.title == "search" }?.value, "clicky repo")
        XCTAssertEqual(elements.first { $0.isSecureField }?.value, "")     // errata B1: never cached
        XCTAssertEqual(elements.first { $0.key.title == "notes" }?.value.count,
                       ElementSnapshot.maxStoredValueLength)
    }
    func testSnapshotsCarryFramesActionsAndSecureFlagsAndDropRolelessNodes() async {
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = FakeAXNode(AXNodeAttributes(role: "AXWindow", title: "Notes"), children: [
            FakeAXNode(AXNodeAttributes()),                                     // no role → dropped
            FakeAXNode(AXNodeAttributes(role: "AXButton", title: "Delete",
                                        frame: CGRect(x: 100, y: 50, width: 30, height: 20),
                                        isEnabled: false, actions: ["AXPress"])),
            FakeAXNode(AXNodeAttributes(role: "AXTextField", subrole: "AXSecureTextField", title: "Password")),
        ])
        let elements = await AXTreeCrawler(source: factory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(elements.count, 3)
        let delete = elements.first { $0.key.title == "delete" }
        XCTAssertEqual(delete?.frame, CGRect(x: 100, y: 50, width: 30, height: 20))
        XCTAssertEqual(delete?.isEnabled, false)
        XCTAssertEqual(delete?.actions, ["AXPress"])
        XCTAssertTrue(elements.contains { $0.isSecureField && $0.key.subrole == "axsecuretextfield" })
    }
}
