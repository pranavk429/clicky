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
}
