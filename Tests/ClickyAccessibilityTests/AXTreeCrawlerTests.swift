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
        var chain = FakeAXNode(AXNodeAttributes(role: "AXStaticText", title: "d8"))
        for depth in stride(from: 7, through: 0, by: -1) {
            chain = FakeAXNode(AXNodeAttributes(role: depth == 0 ? "AXWindow" : "AXGroup", title: "d\(depth)"),
                               children: [chain])
        }
        let depthFactory = FakeAXNodeFactory()
        depthFactory.focusedWindowNode = chain
        let chainElements = await AXTreeCrawler(source: depthFactory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(chainElements.count, 6)                    // depths 0...5
        XCTAssertEqual(chainElements.last?.key.title, "d5")

        let wideFactory = FakeAXNodeFactory()
        wideFactory.focusedWindowNode = FakeAXNode(
            AXNodeAttributes(role: "AXWindow", title: "List"),
            children: (0..<2_500).map { FakeAXNode(AXNodeAttributes(role: "AXStaticText", title: "row \($0)")) })
        let wideElements = await AXTreeCrawler(source: wideFactory).snapshot(focusedWindowOf: 42)
        XCTAssertEqual(wideElements.count, CrawlerBudget.maxNodes)     // 2000
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
