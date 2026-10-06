import AppKit
import ApplicationServices
import ClickyAccessibility
import ClickyAudio
import ClickyCore
import ClickyGemini
import ClickyInput
import ClickyOverlay
import ClickySafety
import ClickyVision
import CoreGraphics
import Foundation

// Chunk-13 adapter layer. This is the ONLY file that names the concrete Chunk 6–11
// APIs; it wires them into the Chunk 12 port protocols that `ToolRouter` consumes.
//
//   ClickyAccessibility:
//     AXTreeCrawler.shared.snapshot(focusedWindowOf:) -> [ElementSnapshot] (flat,
//       focused window first); ElementSnapshot.key (CacheKey.role/subrole/title/
//       description), .frame (global CG, y-down), .isEnabled, .actions
//     AXHotCache.shared.activate(pid:) / speculate() / crawlNow() /
//       lookup(_ query: ElementQuery) -> ScoredElement.snapshot
//   ClickyVision:
//     ScreenFrameSource() / .hasPermission (static) /
//       captureFrontmostWindow(grid:) -> ScreenFrame(jpeg:pixelSize:cursorPoint:)
//       — one frame, in memory only; `grid` composites the labeled overlay
//   ClickyInput:
//     EventSynthesizer.click(element:) / typeText(_:into:preferPaste:) /
//       scroll(_:on:) / pressKey(_:on:) / releaseHeldInput()
//     SecureInputGuard.evaluate(element:) -> SecureInputDecision
//     SystemEventPoster.postKeyChord(keyCode:flags:) (the ⌘⌫ Tier-3 delete path)
//   ClickySafety:
//     IntentLedger.record(_:source:) / authorize(_:)
//     RiskGatekeeper.classify(_:) ; RiskContext / RiskAction ; RiskTier
//     PendingActionGate.present/promptTurnComplete/userSpoke/awaitArmAndRevalidate
//   ClickyAudio: AudioStreamEngine (onInputChunk / onVADEvent / start / stop /
//     beginPlaybackTurn / enqueuePlaybackPCM / stopPlaybackNow)
//   ClickyOverlay: OverlayWindowController.shared.presentMoving/presentReview/
//     presentConfirmation/presentStopped

/// Chunk-13 seam for pre-warming the Chunk 6 AX hot cache. Deliberately not part
/// of `ToolRouter`'s ports (those are frozen); the app injects the concrete
/// adapter and tests may omit it.
protocol ScreenCacheWarming: Sendable {
    /// Activate the observer for the frontmost app and warm the cache (session start).
    func warmFrontmostWindow() async
    /// Speculative refresh on voice onset so the `toolCall` lands on a warm cache.
    func speculateFrontmost() async
}

/// The Chunk 6 accessibility surface behind `ScreenContextProviding` and
/// `SystemActionPort`. AX work stays on this actor, never `@MainActor`.
actor AXEngineAdapter: ScreenContextProviding, SystemActionPort, ScreenCacheWarming {
    /// ANSI Delete (Backspace); ⌘⌫ is the approved Tier-3 `delete_target` mechanism.
    private static let deleteKeyCode: CGKeyCode = 51

    /// Failure reason when an element-targeted action's app cannot be brought
    /// to the front; the action fails closed instead of synthesizing input into
    /// whatever window happens to be frontmost.
    private static let targetActivationFailure = "target app could not be activated"

    /// Brings a target app to the front before element-targeted actuation.
    /// Injected so the activation gate is testable without touching the real
    /// `NSWorkspace`; the default activates a running app by exact
    /// localizedName and waits (bounded) until it is frontmost.
    typealias TargetAppActivation = @Sendable (String) async -> Bool

    private let crawler: AXTreeCrawler
    private let cache: AXHotCache
    private let synthesizer: EventSynthesizer
    private let activateTargetApp: TargetAppActivation
    private var lastWindowTitle = ""

    init(crawler: AXTreeCrawler = .shared, cache: AXHotCache = .shared,
         synthesizer: EventSynthesizer = EventSynthesizer(),
         activateTargetApp: @escaping TargetAppActivation = { name in
             await AXEngineAdapter.defaultActivation(name)
         }) {
        self.crawler = crawler
        self.cache = cache
        self.synthesizer = synthesizer
        self.activateTargetApp = activateTargetApp
    }

    // MARK: ScreenContextProviding

    func captureContext(reason: String, maxNodes: Int) async -> ScreenContext {
        guard let pid = Self.frontmostPID() else {
            return ScreenContext(applicationName: "", windowTitle: "", elements: [])
        }
        let tree = await crawler.snapshot(focusedWindowOf: pid)
        // Decision (a): the crawled focused window snapshot (first, focused window
        // first) supplies `windowTitle` from its `key.title`.
        if let window = tree.first { lastWindowTitle = window.key.title }
        let elements = tree.prefix(max(0, maxNodes)).map { snapshot in
            ScreenContextElement(role: snapshot.key.role,
                                 subrole: snapshot.key.subrole.isEmpty ? nil : snapshot.key.subrole,
                                 title: snapshot.key.title,
                                 elementDescription: snapshot.key.description.isEmpty ? nil : snapshot.key.description,
                                 enabled: snapshot.isEnabled,
                                 actions: snapshot.actions)
        }
        return ScreenContext(applicationName: Self.applicationName(for: pid),
                             windowTitle: lastWindowTitle, elements: Array(elements))
    }

    // MARK: SystemActionPort

    func resolve(title: String?, kind: ClickyActionKind) async -> ResolvedTarget? {
        guard let title, !title.isEmpty, let pid = Self.frontmostPID() else { return nil }
        await cache.activate(pid: pid)
        let query = ElementQuery(text: title)
        if let match = await cache.lookup(query) { return await makeTarget(match.snapshot, pid: pid) }
        await cache.crawlNow()
        guard let match = await cache.lookup(query) else { return nil }
        return await makeTarget(match.snapshot, pid: pid)
    }

    func perform(_ action: ResolvedAction) async -> ActionOutcome {
        switch action.kind {
        case .openURL:
            guard let text = action.text, let url = URL(string: text) else { return .failed(reason: "invalid url") }
            return NSWorkspace.shared.open(url)
                ? .performed(detail: "opened \(url.host ?? text)") : .failed(reason: "open failed")

        case .navigate:
            // One local step: open the URL in a new tab of the named browser
            // (when it is already running) or of the frontmost browser; fall
            // back to the system default browser via NSWorkspace otherwise.
            guard let text = action.text, let url = URL(string: text) else { return .failed(reason: "invalid url") }
            if let name = action.browser {
                guard let browser = Self.runningBrowser(named: name) else {
                    return Self.openInDefaultBrowser(url: url, fallbackReason: "\(name) is not running")
                }
                return await openInBrowser(url: url, browser: browser)
            }
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.activationPolicy == .regular, Self.isBrowser(frontmost) {
                return await openInBrowser(url: url, browser: frontmost)
            }
            return Self.openInDefaultBrowser(url: url, fallbackReason: nil)

        case .switchApp:
            guard let name = action.text else { return .failed(reason: "missing app name") }
            guard let activated = await Self.activate(name: name) else { return .failed(reason: "app not found") }
            return .performed(detail: "switched to \(activated)")

        case .click:
            guard await activateTargetIfNeeded(action.target) else { return .failed(reason: Self.targetActivationFailure) }
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            switch await synthesizer.click(element: element.element) {
            case .axPressed: return .performed(detail: "pressed")
            case .clickFallback: return .performed(detail: "clicked fallback")
            case .noTargetPoint: return .failed(reason: "could not resolve a click point")
            }

        case .clickCursor:
            // "Click here": the pointer is the anchor. The router previews the
            // same point via `pointerLocation()`; re-read it when absent.
            guard let point = action.point ?? CGEvent(source: nil)?.location else {
                return .failed(reason: "could not read the pointer")
            }
            return await clickAtPoint(point)

        case .clickAt:
            guard let point = action.point else { return .failed(reason: "no frame-mapped click point") }
            return await clickAtPoint(point)

        case .clickGrid:
            guard let point = action.point else { return .failed(reason: "no frame-mapped click point") }
            return await clickGridCell(at: point, rect: action.gridRect, cell: action.gridCell)

        case .deleteTarget:
            guard await activateTargetIfNeeded(action.target) else { return .failed(reason: Self.targetActivationFailure) }
            guard let element = await resolveElement(action.target) else { return .failed(reason: "target disappeared") }
            let secure = SecureInputGuard.evaluate(element: element.element)
            guard secure.isAllowed else { return .refused(reason: "secure input: \(secure.rule.rawValue)") }
            // Approved Tier-3 design: focus the resolved target, then ⌘⌫ (the item
            // moves to Recently Deleted; recoverable). No fileURL extraction.
            if case .noTargetPoint = await synthesizer.click(element: element.element) {
                return .failed(reason: "could not focus the target")
            }
            SystemEventPoster().postKeyChord(keyCode: Self.deleteKeyCode, flags: .maskCommand)
            return .performed(detail: "moved to Recently Deleted")

        case .typeText, .paste:
            guard await activateTargetIfNeeded(action.target) else { return .failed(reason: Self.targetActivationFailure) }
            let element = await resolveElement(action.target)
            if let element {
                let secure = SecureInputGuard.evaluate(element: element.element)
                guard secure.isAllowed else { return .refused(reason: "secure input: \(secure.rule.rawValue)") }
            }
            // Fallback: a target with no resolvable AX title (e.g., a blank editor)
            // is typed into at the current keyboard focus. `EventSynthesizer.typeText`
            // runs the SecureInputGuard against the focused element before any
            // keystroke and verifies-or-refuses, so no gate is bypassed.
            let outcome = await synthesizer.typeText(action.text ?? "", into: element?.element,
                                                     preferPaste: action.kind == .paste)
            switch outcome {
            case .directVerified: return .performed(detail: "typed and verified")
            case .pasteboardVerified: return .performed(detail: "pasted and verified")
            case .blocked(let rule): return .refused(reason: "secure input rule: \(rule.rawValue)")
            case .unverified(let reason): return .failed(reason: reason)
            }

        case .scroll:
            guard await activateTargetIfNeeded(action.target) else { return .failed(reason: Self.targetActivationFailure) }
            let element = await resolveElement(action.target)
            return await synthesizer.scroll(action.text ?? "down", on: element?.element)
                ? .performed(detail: "scrolled") : .failed(reason: "scroll failed")

        case .keyPress:
            // Chords like "cmd+t" post to the frontmost app's keyboard focus and
            // need no AX target; a resolvable target is used when present. The
            // synthesizer's secure-input guard runs before any keystroke either way.
            guard await activateTargetIfNeeded(action.target) else { return .failed(reason: Self.targetActivationFailure) }
            let element = await resolveElement(action.target)
            return await synthesizer.pressKey(action.text ?? "", on: element?.element)
                ? .performed(detail: "key pressed") : .failed(reason: "key press failed")
        }
    }

    /// Click-through suppression: macOS activates an inactive window on a
    /// synthetic click without triggering the control, and an AX lookup in the
    /// wrong app resolves the wrong element. Before any element-targeted action,
    /// bring the action's target app to the front and wait (bounded) until it is
    /// frontmost; fail closed when it cannot be activated — input is never
    /// synthesized into the wrong window. Coordinate-anchored actions
    /// (`click_cursor` / `click_at` / `click_grid`) are exempt: frame validity
    /// already pins them to the captured frontmost app.
    private func activateTargetIfNeeded(_ target: ResolvedTarget?) async -> Bool {
        guard let target, !target.applicationName.isEmpty else { return true }
        return await activateTargetApp(target.applicationName)
    }

    /// Default activation: exact (case-insensitive) `localizedName` match among
    /// regular running apps, `.activateAllWindows`, then a bounded wait until
    /// that process is frontmost. Already-frontmost is a no-op; an app that is
    /// not running or does not come forward returns false (fail closed).
    private static func defaultActivation(_ name: String) async -> Bool {
        let normalized = name.lowercased()
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && $0.localizedName?.lowercased() == normalized
        }) else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
        app.activate(from: .current, options: [.activateAllWindows])
        return await waitUntilFrontmost(app)
    }

    // MARK: Pointer-anchored clicks

    /// Global pointer position (AX/CG space, y-down) for the `click_cursor`
    /// preview; nil only when no event source can be read.
    func pointerLocation() async -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Clicks `point` with a synthetic pointer click and describes the element
    /// that sat under it *before* the click, so the model hears what it hit.
    /// `EventSynthesizer.click(at:)` runs the secure-input guard before posting;
    /// pointer clicks are never blocked there (errata B8), so the verdict is
    /// telemetry only.
    private func clickAtPoint(_ point: CGPoint) async -> ActionOutcome {
        let elementDescription = Self.elementDescription(at: point)
        _ = await synthesizer.click(at: point)
        let location = "(\(Int(point.x.rounded())),\(Int(point.y.rounded())))"
        guard let elementDescription else { return .performed(detail: "clicked at \(location)") }
        return .performed(detail: "clicked '\(elementDescription)' at \(location)")
    }

    /// Clicks a resolved grid cell. When the cell's rectangle contains exactly
    /// one distinct labeled AX element, that element is pressed (AX press first;
    /// the synthesizer's synthetic-click fallback lands on the probe point inside
    /// the cell, never on a container-sized element center). Otherwise the cell
    /// center is clicked. The detail names what was clicked, honestly.
    private func clickGridCell(at point: CGPoint, rect: CGRect?, cell: String?) async -> ActionOutcome {
        let cellLabel = cell ?? "the cell"
        if let rect, let probe = Self.singleLabeledElement(in: rect) {
            switch await synthesizer.click(element: probe.element, fallbackPoint: probe.point) {
            case .axPressed, .clickFallback:
                return .performed(detail: "clicked '\(probe.label)' in \(cellLabel)")
            case .noTargetPoint:
                break // fall through to the cell-center click
            }
        }
        _ = await synthesizer.click(at: point)
        return .performed(detail: "clicked cell \(cellLabel) (center)")
    }

    /// Probes a 3×3 lattice inside `rect` (global AX/CG space, y-down) for
    /// labeled elements (title/description). Returns the single distinct labeled
    /// element found, or nil when no probe finds a label or the labels disagree
    /// (ambiguous cell — the caller then clicks the cell center). Window and
    /// application elements are skipped: their labels are chrome, not content,
    /// and their centers can be far outside the cell. The probe point travels
    /// with the element so a failed AX press can fall back to a click there.
    private static func singleLabeledElement(in rect: CGRect) -> (label: String, element: AXUIElement, point: CGPoint)? {
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        var found: (label: String, element: AXUIElement, point: CGPoint)?
        for row in 0..<3 {
            for column in 0..<3 {
                let point = CGPoint(x: rect.minX + rect.width * (CGFloat(column) + 0.5) / 3,
                                    y: rect.minY + rect.height * (CGFloat(row) + 0.5) / 3)
                guard let element = Self.element(at: point),
                      let role = Self.stringAttribute(element, kAXRoleAttribute),
                      role != kAXWindowRole, role != kAXApplicationRole,
                      let label = Self.label(of: element) else { continue }
                if let existing = found, existing.label != label { return nil } // ambiguous cell
                if found == nil { found = (label, element, point) }
            }
        }
        return found
    }

    /// Detail-string description of the element under a global point (AX/CG
    /// space, y-down): the element's own title/description; when the exact
    /// point sits on an unlabeled container, a ±4 px cross probe (4 samples)
    /// for the first labeled element found; the role at the exact point as the
    /// last resort. nil when AX cannot resolve anything. Result detail only —
    /// never a target handle.
    private static func elementDescription(at point: CGPoint) -> String? {
        let exact = Self.element(at: point)
        if let label = Self.label(of: exact) { return label }
        let cross: [CGPoint] = [CGPoint(x: 4, y: 0), CGPoint(x: -4, y: 0),
                                CGPoint(x: 0, y: 4), CGPoint(x: 0, y: -4)]
        for offset in cross {
            let probe = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let label = Self.label(of: Self.element(at: probe)) { return label }
        }
        guard let exact else { return nil }
        return Self.stringAttribute(exact, kAXRoleAttribute)
    }

    /// AX element at a global point; nil when AX cannot resolve one.
    private static func element(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    /// Title, then description of an AX element; nil when neither exists.
    private static func label(of element: AXUIElement?) -> String? {
        guard let element else { return nil }
        return Self.stringAttribute(element, kAXTitleAttribute)
            ?? Self.stringAttribute(element, kAXDescriptionAttribute)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    // MARK: ScreenCacheWarming

    func warmFrontmostWindow() async {
        guard let pid = Self.frontmostPID() else { return }
        await cache.activate(pid: pid)
        await cache.crawlNow()
        if let window = await crawler.snapshot(focusedWindowOf: pid).first { lastWindowTitle = window.key.title }
    }

    func speculateFrontmost() async {
        guard let pid = Self.frontmostPID() else { return }
        await cache.activate(pid: pid)
        await cache.speculate()
    }

    // MARK: Helpers

    private func resolveElement(_ target: ResolvedTarget?) async -> ElementSnapshot? {
        guard let target, let pid = Self.frontmostPID() else { return nil }
        await cache.activate(pid: pid)
        let query = ElementQuery(text: target.title, role: target.role)
        if let match = await cache.lookup(query) { return match.snapshot }
        await cache.crawlNow()
        return await cache.lookup(query)?.snapshot
    }

    private func makeTarget(_ snapshot: ElementSnapshot, pid: pid_t) async -> ResolvedTarget {
        ResolvedTarget(applicationName: Self.applicationName(for: pid),
                       role: snapshot.key.role,
                       subrole: snapshot.key.subrole.isEmpty ? nil : snapshot.key.subrole,
                       title: snapshot.key.title,
                       windowTitle: await windowTitle(for: pid),
                       cgFrame: snapshot.frame)
    }

    private func windowTitle(for pid: pid_t) async -> String {
        if !lastWindowTitle.isEmpty { return lastWindowTitle }
        lastWindowTitle = await crawler.snapshot(focusedWindowOf: pid).first?.key.title ?? ""
        return lastWindowTitle
    }

    private static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Decision (a): `applicationName` is the `NSRunningApplication.localizedName`
    /// for the target pid — no new AX attributes.
    private static func applicationName(for pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    /// Tier-2 `switch_app`: activate an already-running regular app on a spoken-name
    /// match, else open `<name>.app` from the three standard folders. No deprecated
    /// `launchApplication`; no path ever comes from speech.
    private static func activate(name: String) async -> String? {
        let normalized = name.lowercased()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let match = running.first { $0.localizedName?.lowercased() == normalized }
            ?? running.first { $0.bundleIdentifier?.lowercased().hasSuffix(normalized) == true }
            ?? running.first { $0.localizedName?.lowercased().hasPrefix(normalized) == true }
        if let match {
            match.activate(from: .current, options: [.activateAllWindows])
            return match.localizedName ?? name
        }
        let folders = ["/Applications", "/System/Applications",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let target = "\(normalized).app"
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder),
                  let entry = entries.first(where: { $0.lowercased() == target }) else { continue }
            let url = URL(fileURLWithPath: folder).appendingPathComponent(entry)
            if await openApplication(url) { return FileManager.default.displayName(atPath: url.path) }
        }
        return nil
    }

    private static func openApplication(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url,
                                               configuration: NSWorkspace.OpenConfiguration()) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }

    // MARK: navigate

    /// Gap between `navigate`'s synthetic steps (~70 ms, within the 60–80 ms
    /// target) so the browser processes each chord before the next one.
    private static let navigateStepGap: Duration = .milliseconds(70)

    /// Browser-shaped app: the bundle id or localized name contains one of the
    /// known browser markers (case-insensitive). Used only to decide whether
    /// `navigate` may type into the frontmost app; anything else falls back to
    /// `NSWorkspace.open`.
    private static let browserMarkers = ["chrome", "safari", "firefox", "edge", "arc",
                                         "brave", "comet", "opera", "vivaldi", "browser"]
    private static func isBrowser(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        return Self.browserMarkers.contains { name.contains($0) || bundle.contains($0) }
    }

    /// Running-app match for `navigate`'s `browser` argument, in the
    /// AppActivator style (exact name, bundle-id suffix, then name prefix).
    /// Returns nil when the app is not already running — `navigate` then falls
    /// back to `NSWorkspace.open` instead of launching an app from speech.
    private static func runningBrowser(named name: String) -> NSRunningApplication? {
        let normalized = name.lowercased()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return running.first { $0.localizedName?.lowercased() == normalized }
            ?? running.first { $0.bundleIdentifier?.lowercased().hasSuffix(normalized) == true }
            ?? running.first { $0.localizedName?.lowercased().hasPrefix(normalized) == true }
    }

    /// Bounded wait for an activated app to become frontmost, so `navigate`'s
    /// keystrokes can never land in the app that was frontmost before.
    private static func waitUntilFrontmost(_ app: NSRunningApplication, timeout: TimeInterval = 0.8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// The `navigate` sequence: activate the browser, then cmd+t → cmd+l →
    /// type the URL → return, with ~70 ms gaps. Address-bar entry the
    /// synthesizer cannot verify is accepted for this flow (omnibox values are
    /// often not readable) but the detail says so; blocked or failed steps
    /// fail closed.
    private func openInBrowser(url: URL, browser: NSRunningApplication) async -> ActionOutcome {
        let name = browser.localizedName ?? "the browser"
        browser.activate(from: .current, options: [.activateAllWindows])
        guard await Self.waitUntilFrontmost(browser) else {
            return .failed(reason: "\(name) did not come to the front")
        }
        guard await synthesizer.pressKey("cmd+t") else {
            return .failed(reason: "could not open a new tab in \(name)")
        }
        try? await Task.sleep(for: Self.navigateStepGap)
        guard await synthesizer.pressKey("cmd+l") else {
            return .failed(reason: "could not focus the address bar in \(name)")
        }
        try? await Task.sleep(for: Self.navigateStepGap)
        var entryUnverified = false
        switch await synthesizer.typeText(url.absoluteString, into: nil, preferPaste: false) {
        case .directVerified, .pasteboardVerified:
            break
        case .unverified:
            entryUnverified = true
        case .blocked(let rule):
            return .refused(reason: "secure input rule: \(rule.rawValue)")
        }
        try? await Task.sleep(for: Self.navigateStepGap)
        guard await synthesizer.pressKey("return") else {
            return .failed(reason: "could not confirm the address in \(name)")
        }
        let host = url.host ?? url.absoluteString
        return .performed(detail: entryUnverified
            ? "opened \(host) in \(name), new tab (address-bar entry unverified)"
            : "opened \(host) in \(name), new tab")
    }

    /// Fallback: hand the URL to the system default browser, saying in the
    /// detail that the fallback happened (and why). Never reports success when
    /// the fallback itself fails.
    private static func openInDefaultBrowser(url: URL, fallbackReason: String?) -> ActionOutcome {
        guard NSWorkspace.shared.open(url) else { return .failed(reason: "open failed") }
        let host = url.host ?? url.absoluteString
        guard let fallbackReason else { return .performed(detail: "opened \(host) in the default browser") }
        return .performed(detail: "opened \(host) in the default browser — \(fallbackReason)")
    }
}

// MARK: - Live-vision adapter

/// The live-vision seam behind `ScreenLooking` (demo-critical `look_at_screen`).
/// One cursor-marked JPEG of the frontmost window flows straight into the Live
/// session; frames are never written to disk and never logged. After the send,
/// the AX element under the pointer is described so the model can answer
/// precisely ("the Save button under your cursor"). The `notice` closure surfaces
/// a missing Screen Recording permission to the UI once per session.
actor ScreenLookingAdapter: ScreenLooking {
    /// AX values can be long; only a short, privacy-safe slice is reported.
    private static let maxCursorValueLength = 200

    private let source: ScreenFrameSource
    private let notice: (@Sendable (String) -> Void)?
    /// Weak on purpose: `router → adapter → client → router` would otherwise be a
    /// session-lifetime retain cycle (the coordinator owns the strong client ref).
    private weak var client: GeminiLiveClient?
    private var didNoticePermission = false

    // Gaze assist (opt-in via `CLICKY_GAZE=1`): a coarse, on-device camera
    // estimate used only to choose the AX probe point for `look_at_screen` —
    // "the element under your gaze". Camera frames never leave the process and
    // are never written to disk; without the flag, camera, permission, or a
    // face, the cursor path is unchanged. The sampler starts on the first look
    // and stops with this adapter.
    private let gazeEnabled: Bool
    private let gazeGain: Double
    private var gazeSampler: GazeSampler?
    private var didAttemptGazeStart = false

    /// The geometry of the most recently sent frame, kept so `click_at` can map
    /// the model's frame-pixel coordinates back to global screen coordinates and
    /// `click_grid` can map cell labels onto screen rectangles.
    private struct SentFrame {
        let captureRect: CGRect
        let pixelSize: CGSize
        /// Frontmost app at capture time; a frame is only clickable while that
        /// app is still frontmost.
        let applicationName: String?
        let date: Date
        /// The overlay grid drawn onto this frame, when one was requested; nil
        /// means the frame carries no cell labels and `click_grid` fails closed.
        let grid: ScreenGrid?
    }
    private var lastSentFrame: SentFrame?

    init(source: ScreenFrameSource? = nil,
         notice: (@Sendable (String) -> Void)? = nil,
         excludedWindowNumbers: @escaping @Sendable () async -> [CGWindowID] = {
             await MainActor.run { OverlayWindowController.shared.panelWindowIDs }
         }) {
        self.source = source ?? ScreenFrameSource(excludedWindowNumbers: excludedWindowNumbers)
        self.notice = notice
        self.gazeEnabled = ProcessInfo.processInfo.environment["CLICKY_GAZE"] == "1"
        // `CLICKY_GAZE_GAIN` scales offset → screen-point movement; default 0.6.
        // Non-finite or non-positive values fall back to the default.
        let parsedGain = ProcessInfo.processInfo.environment["CLICKY_GAZE_GAIN"].flatMap(Double.init)
        self.gazeGain = parsedGain.map { $0.isFinite && $0 > 0 ? $0 : 0.6 } ?? 0.6
    }

    deinit {
        // Stops the camera. `GazeSampler.stop()` captures its session strongly,
        // so it is safe to call while this adapter is deallocating.
        gazeSampler?.stop()
    }

    /// Breaks the router↔client construction cycle: the coordinator builds this
    /// adapter (held by the router), then the client, and attaches the client
    /// before `live.start()` — so no tool call can observe a nil client.
    func attach(client: GeminiLiveClient) { self.client = client }

    /// Spec §4.1 privacy rule: visual access is off by default for windows whose
    /// titles suggest banking, checkout, payment, or credentials (English and
    /// Devanagari). Over-blocking is the safe direction; the explicit 60 s visual
    /// grant is a follow-up. Checked before any capture or permission prompt.
    private static let sensitiveWindowKeywords = [
        "bank", "checkout", "payment", "password", "credit card", "card number",
        "cvv", "wallet", "upi", "netbanking",
        "बैंक", "भुगतान", "पेमेंट", "पासवर्ड", "कार्ड",
    ]

    private func isSensitiveFrontmostWindow() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
              let title = Self.stringAttribute(window as! AXUIElement, kAXTitleAttribute) else { return false }
        let lowered = title.lowercased()
        return Self.sensitiveWindowKeywords.contains { lowered.contains($0) }
    }

    func lookAtScreen(reason: String, grid: ScreenGrid?) async -> ScreenLookOutcome {
        // Every look attempt starts with no usable frame: only a frame that was
        // actually sent can anchor `click_at`/`click_grid`, so a refused or
        // failed capture (sensitive window, permission, transport) leaves none
        // behind.
        lastSentFrame = nil
        if isSensitiveFrontmostWindow() {
            return .failed(reason: "this window looks sensitive — visual access is off for banking, payment, and password windows")
        }
        if !ScreenFrameSource.hasPermission {
            // First request adds Clicky to System Settings → Screen Recording and
            // shows the system prompt; capture still fails closed until granted.
            // macOS requires an app relaunch after the grant for capture to work.
            _ = CGRequestScreenCaptureAccess()
            noticePermissionDenied()
            return .noPermission
        }
        guard let client else { return .failed(reason: "the live session is not connected") }
        // Gaze assist (opt-in): start the camera on first use, then read the
        // latest coarse sample. Any absence (flag off, no camera or permission,
        // no face yet) silently falls through to the cursor point.
        ensureGazeSampler()
        let gazePoint = currentGazeScreenPoint()
        // Global CG/AX cursor point (y-down), read immediately before the capture
        // so the AX probe matches the marker the frame source draws. `reason` is
        // advisory only — it is never logged and never leaves the session.
        let cursorPoint = CGEvent(source: nil)?.location
        do {
            let frame = try await source.captureFrontmostWindow(
                grid: grid.map { (cols: $0.cols, rows: $0.rows) })
            try await client.sendVideoFrame(jpeg: frame.jpeg)
            lastSentFrame = SentFrame(captureRect: frame.captureRect,
                                      pixelSize: frame.pixelSize,
                                      applicationName: NSWorkspace.shared.frontmostApplication?.localizedName,
                                      date: Date(),
                                      grid: grid)
            return .frameSent(cursor: cursorContext(at: cursorPoint, gazePoint: gazePoint),
                              pixelSize: frame.pixelSize)
        } catch let error as ScreenFrameError {
            switch error {
            case .permissionDenied:
                noticePermissionDenied()
                return .noPermission
            case .noWindow:
                return .failed(reason: "no frontmost window to capture")
            case .captureFailed:
                // Capture internals are never surfaced to the model or logs.
                return .failed(reason: "the screen capture failed")
            }
        } catch GeminiClientError.notReady {
            return .failed(reason: "the live session is not ready")
        } catch GeminiClientError.transportUnavailable {
            return .failed(reason: "the live session connection is unavailable")
        } catch {
            return .failed(reason: "the frame could not be sent")
        }
    }

    /// Maps a `click_at` point from the last sent frame to a global screen
    /// point (AX/CG space, y down). The model may give the point as frame
    /// pixels, `0..1` fractions, or `0..1000` normalized values; ambiguous
    /// values are interpreted in that priority order by
    /// `FramePointInterpreter` (the `look_at_screen` result declares the
    /// frame's exact `frame_size` to steer the model to pixels). Fails closed
    /// (nil) when no frame was sent within `ToolRouter.screenLookFrameValidity`,
    /// when the captured app is no longer frontmost, when the frame geometry is
    /// unusable, or when the interpreted point is outside the frame.
    func mapFramePoint(x: Double, y: Double, at date: Date) async -> CGPoint? {
        // The frame is only clickable while the app it was captured from is
        // still frontmost: coordinates from a stale frame must never click
        // whatever another app has at that spot.
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName else { return nil }
        guard let frame = lastSentFrame,
              frontmost == frame.applicationName,
              date.timeIntervalSince(frame.date) >= 0,
              date.timeIntervalSince(frame.date) <= ToolRouter.screenLookFrameValidity,
              frame.pixelSize.width > 0, frame.pixelSize.height > 0,
              frame.captureRect.width > 0, frame.captureRect.height > 0 else { return nil }
        guard let pixelPoint = FramePointInterpreter.interpretFrameCoordinates(
            x: x, y: y, width: frame.pixelSize.width, height: frame.pixelSize.height) else { return nil }
        let scaleX = frame.captureRect.width / frame.pixelSize.width
        let scaleY = frame.captureRect.height / frame.pixelSize.height
        return CGPoint(x: frame.captureRect.origin.x + pixelPoint.x * scaleX,
                       y: frame.captureRect.origin.y + pixelPoint.y * scaleY)
    }

    /// Maps a grid cell label ("C5", case-insensitive) from the last sent
    /// gridded frame to its global screen rectangle (AX/CG space, y down). Fails
    /// closed exactly like `mapFramePoint`, plus `.invalidCell` when the label is
    /// well-formed but outside the frame's grid. A frame captured without a grid
    /// has no labels the model could have seen, so it maps to `.noFrame`.
    func mapGridCell(_ cell: String, at date: Date) async -> GridCellMapping {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName else { return .noFrame }
        guard let frame = lastSentFrame,
              frontmost == frame.applicationName,
              date.timeIntervalSince(frame.date) >= 0,
              date.timeIntervalSince(frame.date) <= ToolRouter.screenLookFrameValidity,
              frame.pixelSize.width > 0, frame.pixelSize.height > 0,
              frame.captureRect.width > 0, frame.captureRect.height > 0 else { return .noFrame }
        guard let grid = frame.grid else { return .noFrame }
        guard let column = Self.cellColumn(cell), let row = Self.cellRow(cell),
              column < grid.cols, row < grid.rows else { return .invalidCell }
        let cellWidth = frame.pixelSize.width / CGFloat(grid.cols)
        let cellHeight = frame.pixelSize.height / CGFloat(grid.rows)
        let pixelRect = CGRect(x: CGFloat(column) * cellWidth,
                               y: CGFloat(row) * cellHeight,
                               width: cellWidth,
                               height: cellHeight)
        let scaleX = frame.captureRect.width / frame.pixelSize.width
        let scaleY = frame.captureRect.height / frame.pixelSize.height
        return .mapped(rect: CGRect(x: frame.captureRect.origin.x + pixelRect.origin.x * scaleX,
                                    y: frame.captureRect.origin.y + pixelRect.origin.y * scaleY,
                                    width: pixelRect.width * scaleX,
                                    height: pixelRect.height * scaleY))
    }

    /// "C5" → column index 2 (A = 0); nil when the label has no column letter.
    private static func cellColumn(_ cell: String) -> Int? {
        guard let letter = cell.uppercased().first, let ascii = letter.asciiValue,
              ascii >= 65, ascii <= 90 else { return nil }
        return Int(ascii - 65)
    }

    /// "C5" → row index 4 (1 = 0); nil when the label has no row number.
    private static func cellRow(_ cell: String) -> Int? {
        let digits = cell.drop(while: { !$0.isNumber })
        guard let number = Int(digits), number >= 1 else { return nil }
        return number - 1
    }

    private func noticePermissionDenied() {
        guard !didNoticePermission else { return }
        didNoticePermission = true
        notice?("Screen Recording permission is not granted — enable it for Clicky in System Settings → Privacy & Security → Screen Recording, then relaunch Clicky.")
    }

    // MARK: Gaze assist

    /// Starts the gaze sampler on first use when `CLICKY_GAZE=1`. Camera
    /// permission is requested at most once; a denial, a missing camera, or a
    /// failure leaves the sampler stopped and the cursor path untouched
    /// (silent fallback). `start()` is idempotent, so later looks retry cheaply
    /// (e.g., after the user grants Camera in System Settings).
    private func ensureGazeSampler() {
        guard gazeEnabled else { return }
        if let sampler = gazeSampler {
            sampler.start()
            return
        }
        guard !didAttemptGazeStart else { return }
        didAttemptGazeStart = true
        let sampler = GazeSampler()
        gazeSampler = sampler
        Task {
            guard await GazeSampler.requestPermission() else { return }
            sampler.start()
        }
    }

    /// The latest coarse gaze estimate mapped onto the main display (AX/CG
    /// space, y-down), or nil when gaze assist has no usable sample. The map is
    /// `center + offset × gain × half-extent`, clamped to the display bounds.
    private func currentGazeScreenPoint() -> CGPoint? {
        guard gazeEnabled, let sample = gazeSampler?.latest, sample.faceFound else { return nil }
        return GazeSampler.screenPoint(for: sample, gain: gazeGain,
                                       screenBounds: CGDisplayBounds(CGMainDisplayID()))
    }

    /// Describes the AX element under the probe point; degrades to app name +
    /// point when AX is unavailable. When a gaze point is present it is the
    /// probe point ("the element under your gaze") and the cursor point is
    /// reported alongside it. `AXUIElementCopyElementAtPosition` takes global
    /// screen coordinates in AX/CG space (origin top-left, y-down).
    private func cursorContext(at point: CGPoint?, gazePoint: CGPoint?) -> ScreenCursorContext {
        let applicationName = NSWorkspace.shared.frontmostApplication?.localizedName
        let probePoint = gazePoint ?? point
        guard let probePoint else {
            return ScreenCursorContext(applicationName: applicationName)
        }
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(probePoint.x), Float(probePoint.y), &element) == .success,
              let element else {
            return ScreenCursorContext(applicationName: applicationName, point: point, gazePoint: gazePoint)
        }
        let value = Self.stringAttribute(element, kAXValueAttribute)
        return ScreenCursorContext(
            applicationName: applicationName,
            role: Self.stringAttribute(element, kAXRoleAttribute),
            subrole: Self.stringAttribute(element, kAXSubroleAttribute),
            title: Self.stringAttribute(element, kAXTitleAttribute),
            elementDescription: Self.stringAttribute(element, kAXDescriptionAttribute),
            value: value.map { String($0.prefix(Self.maxCursorValueLength)) },
            point: point,
            gazePoint: gazePoint)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

// MARK: - Web access adapter

/// The web-access seam behind `WebAccessing` (`web_search` / `web_fetch`).
/// Keyless DuckDuckGo search and single-page text extraction via `WebFetcher`.
/// Extracted page text flows to the model and is never written to disk or
/// logged; failures map to short, non-content messages.
actor WebAccessAdapter: WebAccessing {
    /// Page text is capped before it reaches the model (the fetcher's default).
    static let maxContentCharacters = 4000
    static let maxSearchResults = 5

    private let fetcher: WebFetcher

    init(fetcher: WebFetcher = WebFetcher()) {
        self.fetcher = fetcher
    }

    func search(query: String) async -> WebAccessOutcome {
        do {
            let results = try await fetcher.search(query: query, maxResults: Self.maxSearchResults)
            let lines = results.enumerated().map { index, result -> String in
                var line = "\(index + 1). \(result.title) — \(result.url.absoluteString)"
                if !result.snippet.isEmpty { line += " — \(result.snippet)" }
                return line
            }
            return .results(lines.joined(separator: "\n"))
        } catch let error as WebError {
            return .failed(Self.message(for: error, isSearch: true))
        } catch {
            return .failed("the search failed")
        }
    }

    func fetch(url urlString: String) async -> WebAccessOutcome {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failed("the url was invalid")
        }
        do {
            let page = try await fetcher.fetch(url: url, maxCharacters: Self.maxContentCharacters)
            var lines: [String] = []
            if let title = page.title, !title.isEmpty { lines.append(title) }
            lines.append(page.url.absoluteString)
            lines.append(page.text)
            return .content(lines.joined(separator: "\n"))
        } catch let error as WebError {
            return .failed(Self.message(for: error, isSearch: false))
        } catch {
            return .failed("the page could not be fetched")
        }
    }

    private static func message(for error: WebError, isSearch: Bool) -> String {
        switch error {
        case .empty:
            return isSearch ? "no results found" : "the page returned no readable text"
        case .invalidURL:
            return isSearch ? "the search query was invalid" : "the url was invalid"
        case .blocked(let detail):
            return "the request was blocked (\(detail))"
        case .transport(let detail):
            return "the request failed (\(detail))"
        }
    }
}

// MARK: - Safety adapters

actor LedgerAdapter: IntentLedgerPort {
    private let ledger = IntentLedger()

    func recordVoiceUtterance(_ text: String, at date: Date) async {
        await ledger.record(text, source: .voice)
    }

    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool {
        let call = IntentLedger.ToolCallIntent(toolName: "execute_action", anchors: [intent])
        switch await ledger.authorize(call) {
        case .authorized: return true
        case .refused: return false
        }
    }
}

struct RiskAdapter: RiskClassifyingPort {
    func classify(kind: ClickyActionKind, text: String?, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier {
        let action: RiskAction
        var url: URL?
        switch kind {
        case .click, .clickCursor, .clickAt, .clickGrid: action = .click
        case .typeText: action = .typeText
        case .paste: action = .clipboardWrite
        case .scroll: action = .navigate
        case .openURL, .navigate:
            // The action's text is the URL; the local gate needs the host for the
            // allowlist check and treats a query string as irreversible egress.
            // `navigate` classifies exactly like `open_url`: same allowlist,
            // same query-string tiering.
            url = URL(string: text ?? "")
            action = .openURL(parameters: url?.query != nil)
        case .switchApp: action = .navigate
        case .deleteTarget: action = .trashFile
        case .keyPress: action = .click
        }
        let effectiveAction = hasAmount ? .financial : action
        let context = RiskContext(action: effectiveAction, targetSubrole: targetSubrole,
                                  targetTitle: targetTitle, url: url)
        return RiskGatekeeper.classify(context).tier
    }
}

actor GateAdapter: ConfirmationGatingPort {
    private let gate: PendingActionGate
    private var pendingContinuation: CheckedContinuation<ConfirmationDecision, Never>?
    private var currentActionID: UUID?
    /// The one live expiry timer for the current `pendingContinuation`. Cancelled and
    /// replaced on every arm (and on resolution) so a superseding arm can never leave
    /// a pending continuation without a timeout.
    private var timeoutTask: Task<Void, Never>?

    init(gate: PendingActionGate = PendingActionGate()) {
        self.gate = gate
    }

    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision {
        let expectedAmount = request.amount.flatMap { Decimal(string: $0) }
        let anchors = request.summary.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty } + [request.summary]
        let action = PendingActionGate.PendingAction(id: request.actionID, description: request.summary,
                                                     tier: request.tier, anchors: anchors,
                                                     expectedAmount: expectedAmount)
        await gate.present(action)
        currentActionID = request.actionID
        return await withCheckedContinuation { continuation in
            if let old = self.pendingContinuation {
                self.pendingContinuation = continuation
                old.resume(returning: .cancelled(reason: "superseded"))
            } else {
                self.pendingContinuation = continuation
            }
            // Every arm owns exactly one live timeout: the superseded continuation was
            // just resumed, so cancel its timer and start one for the new continuation.
            self.timeoutTask?.cancel()
            let timeoutSeconds = max(request.timeoutSeconds, PendingActionGate.minimumTimeout)
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((timeoutSeconds + 2) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.handleTimeout(for: request.actionID)
            }
        }
    }

    func submitVoiceTranscript(_ text: String) async {
        let outcome = await gate.userSpoke(text)
        switch outcome {
        case .accepted:
            if let id = currentActionID {
                let armOutcome = await gate.awaitArmAndRevalidate(id: id) { _ in true }
                switch armOutcome {
                case .execute: resume(with: .confirmed(source: .voiceTranscript))
                case .abort(let reason): resume(with: .cancelled(reason: reason.rawValue))
                }
            } else {
                resume(with: .confirmed(source: .voiceTranscript))
            }
        case .cancelled(let reason):
            resume(with: .cancelled(reason: reason.rawValue))
        case .ignored:
            break
        }
    }

    func submitModelDecision(confirmed: Bool, echo: String) async {
        // No-op: confirmation gate receives ONLY local inputs per errata C3.
    }

    func markPromptTurnComplete() async {
        let latched = await gate.promptTurnComplete()
        // The latched input may have been a voice early affirmative or a card
        // tap; the gate does not track which, and both are local user channels.
        guard latched, let id = currentActionID else { return }
        let armOutcome = await gate.awaitArmAndRevalidate(id: id) { _ in true }
        switch armOutcome {
        case .execute: resume(with: .confirmed(source: .voiceTranscript))
        case .abort(let reason): resume(with: .cancelled(reason: reason.rawValue))
        }
    }

    /// On-screen confirmation card decision (explicit local input). The gate
    /// owns the decision: `.accepted` still runs the ≥500 ms arm window +
    /// TOCTOU revalidation before the continuation resumes; an early tap is
    /// latched by the gate and consumed by `markPromptTurnComplete()`.
    func submitCardDecision(confirmed: Bool) async {
        if confirmed {
            switch await gate.userConfirmed() {
            case .accepted:
                if let id = currentActionID {
                    let armOutcome = await gate.awaitArmAndRevalidate(id: id) { _ in true }
                    switch armOutcome {
                    case .execute: resume(with: .confirmed(source: .switchControl))
                    case .abort(let reason): resume(with: .cancelled(reason: reason.rawValue))
                    }
                } else {
                    resume(with: .confirmed(source: .switchControl))
                }
            case .latched:
                // The tap arrived while the model was still speaking the prompt;
                // the pending `markPromptTurnComplete()` arms and resumes.
                break
            case .ignored:
                // No pending action, already confirming, or the gate refused the
                // direct decision (expired / financial lock): nothing to do.
                break
            }
        } else if await gate.userCancelled() {
            resume(with: .cancelled(reason: "switch control"))
        }
    }

    private func handleTimeout(for actionID: UUID) {
        guard currentActionID == actionID else { return }
        resume(with: .expired)
    }

    private func resume(with decision: ConfirmationDecision) {
        if let cont = pendingContinuation {
            pendingContinuation = nil
            currentActionID = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            cont.resume(returning: decision)
        }
    }
}

// MARK: - Overlay adapter

actor OverlayAdapter: GhostCursorPort {
    func present(_ presentation: GhostCursorPresentation) async {
        await MainActor.run {
            switch presentation {
            case .moving(let point): OverlayWindowController.shared.presentMoving(at: point)
            case .review(let rect, let label): OverlayWindowController.shared.presentReview(rect: rect, label: label)
            case .confirm(let rect, let label): OverlayWindowController.shared.presentConfirmation(rect: rect, label: label)
            case .stopped(let reason): OverlayWindowController.shared.presentStopped(reason: reason)
            }
        }
    }
}

// MARK: - Audio adapter

/// Chunk-13 wrapper around the Chunk 10 `AudioStreamEngine`. The engine's `start()`
/// is synchronous and takes no frame callback, so input is delivered through
/// `onInputChunk`; VAD onsets flow back through `onVADEvent`. Model audio (24 kHz
/// base64 PCM) is enqueued through the same VPIO graph.
actor AudioAdapter: AudioSessionPort {
    private let engine: AudioStreamEngine

    init(engine: AudioStreamEngine = AudioStreamEngine()) {
        self.engine = engine
    }

    func start(onFrame: @escaping @Sendable ([Int16]) -> Void,
               onSpeechOnset: @escaping @Sendable (ContinuousClock.Instant) -> Void) async throws {
        engine.onInputChunk = { chunk in onFrame(chunk.samples) }
        engine.onVADEvent = { event, captureStart in
            if case .speechOnset = event { onSpeechOnset(captureStart) }
        }
        try engine.start()
    }

    func stop() async { engine.stop() }

    func beginPlaybackTurn() async { engine.beginPlaybackTurn() }

    func enqueueModelAudio(_ base64Chunks: [String]) async {
        for chunk in base64Chunks {
            guard let data = Data(base64Encoded: chunk) else { continue }
            engine.enqueuePlaybackPCM(data, sampleRate: 24_000)
        }
    }

    func stopPlaybackNow() async { engine.stopPlaybackNow() }
}

// MARK: - Kill-switch adapter

/// The session's local stop seam. This manager is NOT hotkey-registered: the app's
/// single ⌘⇧X registration lives in `AppDelegate.installHotKeys()`. `start(onStop:)`
/// observes `KillSwitchManager.notificationName` and delivers a full session stop
/// for the ⌘⇧X / menu sources only; voice onset is a barge-in (playback stop) and
/// never ends the session. The registered manager's own latch is re-armed by the app
/// at each `.listening` transition (see `AppDelegate`), because this actor cannot see
/// that instance.
actor KillSwitchAdapter: StopSignalPort, KillSwitchPort {
    private let manager: KillSwitchManager
    private let playbackStop: @Sendable () -> Void
    private let releaseInput: @Sendable () -> Void
    private var observer: NSObjectProtocol?
    private var onStop: (@Sendable (StopReason) -> Void)?

    init(playbackStop: @escaping @Sendable () -> Void,
         releaseInput: @escaping @Sendable () -> Void = { KillSwitchManager.releaseSyntheticInputNow() }) {
        self.playbackStop = playbackStop
        self.releaseInput = releaseInput
        self.manager = KillSwitchManager(hooks: KillSwitchManager.Hooks(
            stopPlayback: playbackStop,
            releaseSyntheticInput: releaseInput,
            presentBanner: { _ in },
            stopSession: {}))
    }

    func start(onStop: @escaping @Sendable (StopReason) -> Void) async {
        self.onStop = onStop
        manager.reset()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: KillSwitchManager.notificationName,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let source = note.object as? KillSwitchManager.Source,
                  source == .hotKey || source == .menuBar else { return }
            Task { await self?.deliverStop() }
        }
    }

    func stop() async {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        onStop = nil
    }

    /// Re-arms this session's own (VAD barge-in) latch. The registered ⌘⇧X
    /// manager's latch is reset separately by the app at `.listening`.
    func resetLatch() async { manager.reset() }

    func triggerBargeIn(onset: ContinuousClock.Instant) async {
        manager.triggerBargeIn(source: .voiceOnset, onset: onset)
    }

    /// `ToolRouter`'s circuit-breaker escalation port (spec §4.4): a latched breaker
    /// must stop the session. Delivered directly and unconditionally — it neither
    /// consults the barge-in latch (a prior voice onset on the same manager must not
    /// swallow the escalation) nor routes through the notification observer (which
    /// may not be registered yet during the connect window). Playback and synthetic
    /// input are released first, then the session stop is delivered.
    func triggerKillSwitch(source: String) async {
        playbackStop()
        releaseInput()
        deliverStop()
    }

    private func deliverStop() {
        onStop?(.killSwitch)
    }
}
