import AppKit
import ApplicationServices
import XCTest
@testable import ClickyAccessibility

/// Live checks against the real AX server. Both tests skip unless CLICKY_AX_LIVE=1
/// AND the host terminal has Accessibility permission (a child process inherits
/// the terminal's TCC responsibility).
final class AXLiveCrawlTests: XCTestCase {
    func testLiveCrawlOfFrontmostApp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLICKY_AX_LIVE"] == "1" && AXIsProcessTrusted(),
                          "set CLICKY_AX_LIVE=1 and grant your terminal Accessibility (chunk 6 acceptance)")
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier ?? ProcessInfo.processInfo.processIdentifier
        let start = Date()
        let elements = await AXTreeCrawler(source: RealAXNodeFactory()).snapshot(focusedWindowOf: pid)
        let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
        print("AX live crawl: \(elements.count) elements in \(milliseconds) ms (pid \(pid))")
        XCTAssertFalse(elements.isEmpty,
                       "focused window of \(front?.localizedName ?? "the test process") should expose AX elements")
        XCTAssertEqual(AXTreeCrawler.installGlobalMessagingTimeout(), .success)
    }
    func testLiveWebTreeAdapter() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CLICKY_AX_LIVE"] == "1" && AXIsProcessTrusted(),
                          "set CLICKY_AX_LIVE=1 and grant your terminal Accessibility (chunk 6 acceptance)")
        guard let raw = environment["CLICKY_AX_PID"], let pid = Int32(raw) else {
            throw XCTSkip("set CLICKY_AX_PID to an Electron/Chromium app pid (e.g. pgrep -x Code)")
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let family = AXAppFamily.detect(appBundleURL: app?.bundleURL)
        let restore = AXAppAdapters.enableWebTreeIfNeeded(pid: pid, family: family)
        // Calibrated to the measured Electron wake (~2.1 s, VS Code 1.140.0 /
        // Antigravity IDE, 2026-10-06); the 150 ms default is the plan constant,
        // not a measurement. B6: measure per app.
        AXAppAdapters.wakeRetryDelayMilliseconds = 2_500
        let woke = await AXAppAdapters.waitForTreeWake(pid: pid)
        restore?()
        print("AX adapter: family=\(family) treeWake=\(woke) pid=\(pid)")
        XCTAssertNotEqual(family, .native, "CLICKY_AX_PID should point at an Electron/Chromium app")
        XCTAssertTrue(woke, "expected an AXWebArea under the focused window")
    }
}
