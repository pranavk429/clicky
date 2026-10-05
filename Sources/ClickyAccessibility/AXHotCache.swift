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
    /// A pid change drops the previous app's entries so its targets can never be
    /// looked up; a dead observer is re-armed even for the same pid.
    public func activate(pid: pid_t) {
        if pid != activePID {
            entries.removeAll()
        }
        if pid != activePID || observer?.isLive != true {
            observer?.stop()
            let bridge = AXStructureObserver(pid: pid) { [weak self] in
                Task { await self?.structureChanged() }
            }
            observer = bridge.start() ? bridge : nil
        }
        activePID = pid          // crawl path must target the new app even when observer creation fails
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
        guard pid == activePID else { return }   // app switched mid-crawl — never publish another app's result
        if !fresh.isEmpty { entries = fresh }    // keep the previous flatten through transient AX failures
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
    private var installedNotifications: [String] = []

    init(pid: pid_t, onEvent: @escaping () -> Void) {
        self.pid = pid
        self.onEvent = onEvent
    }
    /// `true` when the observer was created AND at least one structure
    /// notification armed; a failed registration leaves it `false` so
    /// `AXHotCache` can re-arm on the next activation.
    var isLive: Bool { observer != nil && !installedNotifications.isEmpty }

    /// Last-resort teardown only (owner teardown goes through `stop()`): detach
    /// synchronously when the owner never called `stop()`; safe no-op once detached.
    deinit { detachLastResort() }

    /// Returns whether the observer is live after the call: `false` only when
    /// `AXObserverCreate` fails; `true` when already started.
    @discardableResult
    func start() -> Bool {
        guard observer == nil else { return true }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return false }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        installedNotifications = Self.notifications.filter {
            AXObserverAddNotification(created, app, $0 as CFString, refcon) == .success
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        appElement = app
        return true
    }
    /// Owner-initiated teardown. Callbacks are delivered on the main run loop, so
    /// the detach runs there too; the block's `[self]` capture keeps the bridge
    /// (and its live `AXObserver`/run-loop source) retained until main has drained,
    /// so once the source is removed no callback can be in flight — which is what
    /// makes the C callback's `takeUnretainedValue()` safe.
    func stop() {
        guard let observer else { return }
        let notes = installedNotifications
        let app = appElement
        self.observer = nil
        self.appElement = nil
        self.installedNotifications = []
        let teardown = { [self] in
            self.detach(observer: observer, app: app, notes: notes)
        }
        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.async(execute: teardown)
        }
    }
    private func detach(observer: AXObserver, app: AXUIElement?, notes: [String]) {
        if let app {
            for note in notes {
                AXObserverRemoveNotification(observer, app, note as CFString)
            }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    /// Synchronous last-resort detach for `deinit` when `stop()` was never called;
    /// a no-op once `stop()` has cleared the stored observer.
    private func detachLastResort() {
        guard let observer else { return }
        let notes = installedNotifications
        let app = appElement
        self.observer = nil
        self.appElement = nil
        self.installedNotifications = []
        detach(observer: observer, app: app, notes: notes)
    }
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        Unmanaged<AXStructureObserver>.fromOpaque(refcon).takeUnretainedValue().onEvent()
    }
}
