import AppKit
import Foundation

/// OS seam for the web-tree wake (AGENTS.md §6): `AXTreeCrawler` depends on this
/// protocol, production uses `SystemAXWebTreeWaker`, and tests inject fakes so the
/// first-entry gate and re-crawl policy run without AX IPC.
protocol AXWebTreeWaking: Sendable {
    /// File-system family detection for `pid` (runs at most once per app session).
    func detectFamily(of pid: pid_t) -> AXAppFamily
    /// Sets the family's web-tree attribute; returns the restore closure, or nil
    /// for native apps / a failed set.
    func enableWebTreeIfNeeded(pid: pid_t, family: AXAppFamily) -> (() -> Void)?
    /// Bounded probe for the asynchronously built web tree (probe → retry → probe).
    func waitForTreeWake(pid: pid_t) async -> Bool
}

/// Production conformance: delegates to `AXAppAdapters`. The set and the probe
/// perform synchronous AX IPC; the crawler actor calls them off `@MainActor`, as
/// the adapter docs require.
struct SystemAXWebTreeWaker: AXWebTreeWaking {
    func detectFamily(of pid: pid_t) -> AXAppFamily {
        AXAppFamily.detect(appBundleURL: NSRunningApplication(processIdentifier: pid)?.bundleURL)
    }
    func enableWebTreeIfNeeded(pid: pid_t, family: AXAppFamily) -> (() -> Void)? {
        AXAppAdapters.enableWebTreeIfNeeded(pid: pid, family: family)
    }
    func waitForTreeWake(pid: pid_t) async -> Bool {
        await AXAppAdapters.waitForTreeWake(pid: pid)
    }
}

/// Per-pid wake bookkeeping, one entry per app session: the detected family is
/// memoized (the attribute is set at most once per pid) and the restore closure
/// from the wake is retained for `AXAppAdapters.restoreAll()`. Lock-guarded: the
/// crawler actor owns today's access, but the lifecycle teardown that will call
/// `restoreAll()` may run on another executor. Pid reuse within one process
/// lifetime is not distinguished; entries live until `restoreAll()`.
final class AXWebTreeWakeRegistry: @unchecked Sendable {
    static let shared = AXWebTreeWakeRegistry()
    private let lock = NSLock()
    private var families: [pid_t: AXAppFamily] = [:]
    private var restores: [pid_t: () -> Void] = [:]

    init() {}

    /// Reports `pid`'s family, running `detect` only the first time the pid is
    /// seen. `firstEntry` is true exactly once per pid — the crawl that arms the
    /// wake. Native apps are memoized too, so later crawls are a dictionary read.
    func familyAndFirstEntry(pid: pid_t, detect: (pid_t) -> AXAppFamily) -> (family: AXAppFamily, firstEntry: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let family = families[pid] { return (family, false) }
        let family = detect(pid)
        families[pid] = family
        return (family, true)
    }

    /// Retains a successful wake's restore closure. A failed wake (nil) stores
    /// nothing — and the memoized family keeps it from being retried this session.
    func storeRestore(pid: pid_t, restore: (() -> Void)?) {
        guard let restore else { return }
        lock.lock()
        defer { lock.unlock() }
        restores[pid] = restore
    }

    /// Invokes every retained restore exactly once, then forgets all pids so a
    /// later crawl re-detects and re-arms from a clean slate.
    func restoreAll() {
        lock.lock()
        let closures = Array(restores.values)
        restores.removeAll()
        families.removeAll()
        lock.unlock()
        for restore in closures { restore() }
    }
}

extension AXAppAdapters {
    /// Restores every app whose web tree Clicky woke to the attribute value found
    /// before the wake, and clears the per-pid memoization. Reserved for
    /// app-lifecycle teardown (quit / demo end); **nothing calls it yet** — wiring
    /// it is a future lifecycle task. Intended to run with no crawl in flight.
    public static func restoreAll() {
        AXWebTreeWakeRegistry.shared.restoreAll()
    }
}
