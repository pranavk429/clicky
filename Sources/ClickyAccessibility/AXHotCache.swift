import ApplicationServices
import Foundation

/// Per-app AX hot cache (spec §4.5): one `AXObserver` per frontmost app, 100 ms
/// debounce, speculative crawl on VAD onset/app activation, TOCTOU
/// `revalidate(key:against:)`. AX work stays on this actor; the observer only enqueues.
public actor AXHotCache {
    public static let shared = AXHotCache(crawler: .shared)

    private let crawler: AXTreeCrawler
    private var entries: [ElementSnapshot] = []
    private var observer: AXStructureObserver?
    private var activePID: pid_t?
    private var debounceTask: Task<Void, Never>?

    public init(crawler: AXTreeCrawler) {
        self.crawler = crawler
    }
    /// Switch the observer to `pid` (call on app activation) and warm the cache.
    public func activate(pid: pid_t) {
        if pid != activePID {
            observer?.stop()
            let bridge = AXStructureObserver(pid: pid) { [weak self] in
                Task { await self?.structureChanged() }
            }
            bridge.start()
            observer = bridge
            activePID = pid
        }
        scheduleRefresh(afterMilliseconds: 0)
    }
    /// Collapse AXObserver bursts (spec §4.5.3) — 100 ms turns a keystroke storm into one crawl.
    public func structureChanged() {
        scheduleRefresh(afterMilliseconds: CrawlerBudget.debounceMilliseconds)
    }
    /// Speculative crawl on VAD onset (spec §4.5.3, Validation 01 §3.3): warm before the `toolCall` lands.
    public func speculate() {
        scheduleRefresh(afterMilliseconds: 0)
    }
    /// Deterministic refresh — pre-warm callers and tests.
    public func crawlNow() async {
        await refresh()
    }
    /// Best target for a voice-derived query (the matcher excludes secure fields).
    public func lookup(_ query: ElementQuery) -> ScoredElement? {
        ElementMatcher.bestMatch(for: query, in: entries)
    }
    /// TOCTOU seam (errata F-must #4): re-read the element before the hardware
    /// action; AXObserver covers structure, not value/text changes. Fail-closed —
    /// a mismatch drops the entry so a stale snapshot can never be acted on.
    public func revalidate(key: CacheKey, against element: AXUIElement) async -> Bool {
        let attributes = await crawler.attributes(of: element)
        let current = CacheKey(role: attributes.role ?? "", subrole: attributes.subrole ?? "",
                               title: attributes.title ?? "", description: attributes.description ?? "")
        guard current == key else {
            entries.removeAll { $0.key == key }
            return false
        }
        return true
    }
    private func scheduleRefresh(afterMilliseconds delay: Int) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
    private func refresh() async {
        guard let pid = activePID else { return }
        let fresh = await crawler.snapshot(focusedWindowOf: pid)
        if !fresh.isEmpty { entries = fresh }   // keep the previous flatten through transient AX failures
    }
}

/// One observer per app (spec §4.5.1). The run-loop source attaches to the MAIN
/// run loop — the only run loop guaranteed to be running — but the callback only
/// enqueues into `AXHotCache`; no AX IPC happens on main.
final class AXStructureObserver {
    private static let notifications = [
        kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification, kAXFocusedUIElementChangedNotification,
    ]

    private let pid: pid_t
    private let onEvent: () -> Void
    private var observer: AXObserver?
    private var appElement: AXUIElement?

    init(pid: pid_t, onEvent: @escaping () -> Void) {
        self.pid = pid
        self.onEvent = onEvent
    }
    deinit { stop() }

    func start() {
        guard observer == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in Self.notifications {
            AXObserverAddNotification(created, app, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        appElement = app
    }
    func stop() {
        guard let observer else { return }
        if let appElement {
            for note in Self.notifications {
                AXObserverRemoveNotification(observer, appElement, note as CFString)
            }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
        appElement = nil
    }
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        Unmanaged<AXStructureObserver>.fromOpaque(refcon).takeUnretainedValue().onEvent()
    }
}
