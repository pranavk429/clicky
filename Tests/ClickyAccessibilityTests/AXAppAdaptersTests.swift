import XCTest
@testable import ClickyAccessibility

final class AXAppAdaptersTests: XCTestCase {
    private func makeBundle(withFramework name: String?) throws -> URL {
        let app = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Fake-\(UUID().uuidString).app", isDirectory: true)
        let frameworks = app.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        if let name {
            FileManager.default.createFile(atPath: frameworks.appendingPathComponent(name).path, contents: Data())
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        return app
    }
    func testDetectsElectronAndChromiumAndNative() throws {
        let electron = try makeBundle(withFramework: "Electron Framework.framework")
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: electron), .electron)
        let chromium = try makeBundle(withFramework: "Chromium Framework.framework")
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: chromium), .chromium)
        let native = try makeBundle(withFramework: nil)
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: native), .native)
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: nil), .native)
    }
    func testDetectsVendorBrandedChromiumFork() throws {
        // Comet and other Chromium forks rename the framework after the product
        // (verified: Comet.app contains only "Comet Framework.framework").
        let comet = try makeBundle(withFramework: "Comet Framework.framework")
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: comet), .chromium)
        let vendor = try makeBundle(withFramework: "Acme Framework.framework")
        XCTAssertEqual(AXAppFamily.detect(appBundleURL: vendor), .chromium)
    }
    func testAttributeNamesAndRetryBudget() {
        XCTAssertEqual(AXAppAdapters.electronAttribute, "AXManualAccessibility")
        XCTAssertEqual(AXAppAdapters.chromiumAttribute, "AXEnhancedUserInterface")
        XCTAssertEqual(AXAppAdapters.wakeRetryDelayMilliseconds, 150)   // unverified default; configurable
    }
    func testWakeProbeFindsDeeplyNestedWebArea() {
        var chain = FakeAXNode(AXNodeAttributes(role: "AXWebArea"))
        for _ in 0..<7 { chain = FakeAXNode(AXNodeAttributes(role: "AXGroup"), children: [chain]) }
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = chain
        XCTAssertTrue(AXAppAdapters.hasWebArea(factory: factory, pid: 42))
    }
    func testWakeProbeSharesTheCrawlerDepthBudget() {
        // A negative probe must rule out what the re-crawl can reach: the probe
        // searches the same depth range as `CrawlerBudget` (only the node cap is
        // probe-local).
        XCTAssertEqual(AXAppAdapters.wakeProbeMaxDepth, CrawlerBudget.maxDepth)
    }
    func testWakeProbeRespectsItsDepthBudget() {
        func chain(wraps: Int) -> FakeAXNode {
            var chain = FakeAXNode(AXNodeAttributes(role: "AXWebArea"))
            for _ in 0..<wraps { chain = FakeAXNode(AXNodeAttributes(role: "AXGroup"), children: [chain]) }
            return chain
        }
        // At the shared depth cap the probe finds `AXWebArea`; one level deeper
        // it fails, exactly like the crawler's own depth gate.
        let atCap = FakeAXNodeFactory()
        atCap.focusedWindowNode = chain(wraps: CrawlerBudget.maxDepth)
        XCTAssertTrue(AXAppAdapters.hasWebArea(factory: atCap, pid: 42))
        let pastCap = FakeAXNodeFactory()
        pastCap.focusedWindowNode = chain(wraps: CrawlerBudget.maxDepth + 1)
        XCTAssertFalse(AXAppAdapters.hasWebArea(factory: pastCap, pid: 42))
    }
}
