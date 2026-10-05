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
    func testWakeProbeRespectsItsDepthBudget() {
        var chain = FakeAXNode(AXNodeAttributes(role: "AXWebArea"))
        for _ in 0..<12 { chain = FakeAXNode(AXNodeAttributes(role: "AXGroup"), children: [chain]) }
        let factory = FakeAXNodeFactory()
        factory.focusedWindowNode = chain
        XCTAssertFalse(AXAppAdapters.hasWebArea(factory: factory, pid: 42))
    }
}
