import ApplicationServices
import Foundation

/// Family detection for web-tree enablement (spec §4.2.3). Electron bundles
/// `Electron Framework.framework`; Chromium-family browsers bundle a
/// `* Chromium Framework*` / vendor chrome framework. File-system based, unit-tested.
public enum AXAppFamily: Equatable, Sendable {
    case native, electron, chromium

    public static func detect(appBundleURL: URL?) -> AXAppFamily {
        guard let url = appBundleURL else { return .native }
        let frameworks = url.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) else { return .native }
        if entries.contains(where: { $0.hasPrefix("Electron Framework") }) { return .electron }
        if entries.contains(where: { $0.contains("Chromium Framework") || $0.contains("Chrome Framework") }) { return .chromium }
        return .native
    }
}

public enum AXAppAdapters {
    /// Electron PR #10305 ("Special attribute for macOS accessibility", 2017) is
    /// the origin of `AXManualAccessibility` — it exists precisely because
    /// `AXEnhancedUserInterface` is reserved by VoiceOver (errata B5; Report 03's
    /// #25126 citation was wrong). Chromium/Chrome uses `AXEnhancedUserInterface`;
    /// its community-reported window-snapping caveat is unverified.
    public static let electronAttribute = "AXManualAccessibility"
    public static let chromiumAttribute = "AXEnhancedUserInterface"

    /// UNVERIFIED per app (errata B6): Electron wakes its tree ~50–200 ms after
    /// the attribute is set. Keep this configurable and measure per app.
    /// Set this once before concurrent wake-probe use (read on every probe);
    /// it is a process-global tuning knob.
    public static var wakeRetryDelayMilliseconds = 150

    /// Ensures `pid` exposes a web AX tree. Returns a restore closure that puts
    /// the attribute back exactly as Clicky found it — a no-op when it was
    /// already true (VoiceOver owns it then, so enabling never breaks another
    /// AT). Returns nil for native apps or when nothing could be set. Fallback:
    /// after one retry the caller proceeds regardless; a still-empty tree yields
    /// an empty crawl, which routes execution to Tier 2/3. Performs synchronous
    /// AX IPC (copy + set, bounded by the 0.25 s global messaging timeout), so
    /// callers must invoke it from a background executor, never from `@MainActor`.
    @discardableResult
    public static func enableWebTreeIfNeeded(pid: pid_t, family: AXAppFamily) -> (() -> Void)? {
        let attribute: String
        switch family {
        case .native: return nil
        case .electron: attribute = electronAttribute
        case .chromium: attribute = chromiumAttribute
        }
        let app = AXUIElementCreateApplication(pid)
        var current: CFTypeRef?
        let read = AXUIElementCopyAttributeValue(app, attribute as CFString, &current)
        let noop: () -> Void = {}
        if read == .success, (current as? Bool) == true { return noop }   // already enabled — leave it alone
        guard AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue) == .success else {
            return nil
        }
        let previous: CFTypeRef = read == .success ? (current ?? kCFBooleanFalse) : kCFBooleanFalse
        return {
            // Restore what Clicky found; for an unsupported/unset attribute `false`
            // is the closest supported representation (attributes cannot be removed).
            _ = AXUIElementSetAttributeValue(app, attribute as CFString, previous)
        }
    }
    /// Probes for `AXWebArea` under the app's focused window (budgeted crawl);
    /// retries once after `wakeRetryDelayMilliseconds` because the web tree is
    /// built asynchronously after enablement (B6).
    public static func waitForTreeWake(pid: pid_t) async -> Bool {
        let crawler = AXTreeCrawler(source: RealAXNodeFactory())
        if await hasWebArea(crawler, pid: pid) { return true }
        // `wakeRetryDelayMilliseconds` is a public knob: clamp it so a negative value
        // cannot trap the sleep conversion. Cancellation fails closed — no second probe
        // for a caller that no longer wants the answer.
        do {
            try await Task.sleep(for: .milliseconds(max(0, wakeRetryDelayMilliseconds)))
        } catch {
            return false
        }
        return await hasWebArea(crawler, pid: pid)
    }
    static func hasWebArea(_ crawler: AXTreeCrawler, pid: pid_t) async -> Bool {
        let elements = await crawler.snapshot(focusedWindowOf: pid)
        return elements.contains { $0.key.role == "axwebarea" }
    }
}
