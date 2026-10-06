import ApplicationServices
import CoreGraphics
import Foundation

/// Everything the traversal core needs from one node, normalized, from ONE
/// batched IPC fetch (`AXUIElementCopyMultipleAttributeValues`, options 0):
/// per-attribute failures arrive as error boxes and fail the typed casts below;
/// batching is per element, so a 2000-node flatten still costs ~1 IPC/node (B3).
public struct AXNodeAttributes: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var description: String?
    public var placeholder: String?
    public var value: String?
    public var frame: CGRect?
    public var isEnabled: Bool?
    public var actions: [String]

    public init(role: String? = nil, subrole: String? = nil, title: String? = nil, description: String? = nil,
                placeholder: String? = nil, value: String? = nil, frame: CGRect? = nil,
                isEnabled: Bool? = nil, actions: [String] = []) {
        self.role = role; self.subrole = subrole; self.title = title; self.description = description
        self.placeholder = placeholder; self.value = value; self.frame = frame
        self.isEnabled = isEnabled; self.actions = actions
    }
}

/// OS seam (AGENTS.md §6): unit tests inject fakes; the app uses `RealAXNodeFactory`.
public protocol AXNode: AnyObject {
    var element: AXUIElement { get }
    func children() -> [any AXNode]
    func attributes() -> AXNodeAttributes
}

public protocol AXNodeFactory: AnyObject {
    func focusedWindow(of pid: pid_t) -> (any AXNode)?
    func node(for element: AXUIElement) -> any AXNode
}

/// Focused-window flattener (spec §4.2/§4.5): BFS, depth ≤ 12 / ≤ 2000 nodes via
/// `CrawlerBudget` (depth raised from the spec's 5 — user-approved 2026-10-06 —
/// so depth-7 `AXWebArea` content is reachable), one batched fetch per node. The
/// first crawl of an Electron/Chromium pid arms the web-tree wake and may
/// re-crawl once after a bounded probe (see `snapshot(focusedWindowOf:)`). AX
/// work stays on this actor, never `@MainActor`.
public actor AXTreeCrawler {
    public static let shared = AXTreeCrawler(source: RealAXNodeFactory())
    private let source: any AXNodeFactory
    private let waker: any AXWebTreeWaking
    private let wakeRegistry: AXWebTreeWakeRegistry

    public init(source: any AXNodeFactory) {
        self.init(source: source, waker: SystemAXWebTreeWaker(), wakeRegistry: .shared)
    }
    /// Test seam (AGENTS.md §6): inject a fake waker and an isolated registry.
    init(source: any AXNodeFactory, waker: any AXWebTreeWaking, wakeRegistry: AXWebTreeWakeRegistry) {
        self.source = source
        self.waker = waker
        self.wakeRegistry = wakeRegistry
    }
    /// Errata B2: set ONCE on the system-wide element ("globally for this process");
    /// per-element wrapping is NOT equivalent. `RealAXNodeFactory` calls this on init.
    @discardableResult
    public static func installGlobalMessagingTimeout() -> AXError {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), CrawlerBudget.interfaceTimeoutSeconds)
    }
    /// Crawl the app's focused window (PID path). The first crawl of a
    /// web-family app arms the web-tree wake (`AXManualAccessibility` /
    /// `AXEnhancedUserInterface`); if that first flatten shows no `AXWebArea`,
    /// one bounded wake probe runs and the crawl repeats once — the tree builds
    /// asynchronously (~2.05–2.15 s measured for Electron), so the crawl is
    /// never blocked for the build. Native apps take one memoized dictionary
    /// read and nothing else. Empty on AX failure — callers fall back.
    public func snapshot(focusedWindowOf pid: pid_t) async -> [ElementSnapshot] {
        let wakeArmed = armWebTreeWakeIfNeeded(pid: pid)
        guard let root = source.focusedWindow(of: pid) else { return [] }
        let first = flatten(root)
        guard wakeArmed, !Self.exposesWebArea(first) else { return first }
        // Only a positive probe (probe → wakeRetryDelayMilliseconds → probe)
        // justifies the extra flatten: the probe searches the same depth range as
        // `CrawlerBudget`, so a negative probe means a re-crawl cannot surface
        // web content — the next natural crawl picks up the finished tree instead.
        guard await waker.waitForTreeWake(pid: pid) else { return first }
        guard let postWakeRoot = source.focusedWindow(of: pid) else { return first }
        let second = flatten(postWakeRoot)
        return second.isEmpty ? first : second   // keep the first flatten through a transient rebuild
    }
    /// Crawl a window element the caller already holds (app-activation path).
    public func snapshot(focusedWindow element: AXUIElement) -> [ElementSnapshot] {
        flatten(source.node(for: element))
    }
    /// Batched attribute read for TOCTOU revalidation and wake probing.
    public func attributes(of element: AXUIElement) -> AXNodeAttributes {
        source.node(for: element).attributes()
    }
    private func flatten(_ root: any AXNode) -> [ElementSnapshot] {
        var snapshots: [ElementSnapshot] = []
        var queue: [(node: any AXNode, depth: Int)] = [(root, 0)]
        var index = 0
        var visited = 0
        while index < queue.count {
            let (node, depth) = queue[index]
            index += 1
            guard CrawlerBudget.allows(depth: depth, visitedNodes: visited) else { break }
            visited += 1
            if let snapshot = Self.makeSnapshot(attributes: node.attributes(), element: node.element) {
                snapshots.append(snapshot)
            }
            guard depth < CrawlerBudget.maxDepth else { continue }
            for child in node.children() { queue.append((child, depth + 1)) }
        }
        return snapshots
    }
    /// First-entry gate for the wake: family detection and the attribute set run
    /// at most once per pid per app session (memoized in `wakeRegistry`). Returns
    /// true only when this call armed the wake and the tree may still be building.
    /// Synchronous AX IPC on the crawler's executor — never `@MainActor`. The real
    /// AX path cannot be unit-tested; `AXWebTreeWakeTests` covers the policy with
    /// fakes and carries the `[manual OS check]` steps for live apps.
    private func armWebTreeWakeIfNeeded(pid: pid_t) -> Bool {
        let waker = self.waker
        let (family, firstEntry) = wakeRegistry.familyAndFirstEntry(pid: pid) { waker.detectFamily(of: $0) }
        guard firstEntry, family != .native else { return false }
        let restore = waker.enableWebTreeIfNeeded(pid: pid, family: family)
        wakeRegistry.storeRestore(pid: pid, restore: restore)
        return restore != nil
    }
    /// Web-content signal for the re-crawl gate: the same `AXWebArea` the wake
    /// probe searches for, observed in an already-flattened crawl (roles are
    /// normalized to lowercase by `CacheKey`).
    private static func exposesWebArea(_ snapshots: [ElementSnapshot]) -> Bool {
        snapshots.contains { $0.key.role == "axwebarea" }
    }
    /// Pure projection (unit-tested via fakes); role-less nodes cannot be action targets, so they are dropped.
    static func makeSnapshot(attributes: AXNodeAttributes, element: AXUIElement) -> ElementSnapshot? {
        guard let role = attributes.role, !role.isEmpty else { return nil }
        let isSecure = ElementSnapshot.looksSecure(role: role, subrole: attributes.subrole,
                                                   title: attributes.title, placeholder: attributes.placeholder)
        return ElementSnapshot(
            element: element,
            key: CacheKey(role: role, subrole: attributes.subrole ?? "",
                          title: attributes.title ?? "", description: attributes.description ?? ""),
            frame: attributes.frame ?? .zero,
            isEnabled: attributes.isEnabled ?? true,
            isSecureField: isSecure,
            actions: attributes.actions,
            value: ElementSnapshot.storedValue(attributes.value ?? "", isSecure: isSecure))
    }
}

/// Real IPC-backed node. AX positions are global top-left (y down) already — no
/// conversion may happen here; AppKit/CG flips stay in `ClickyCore.CoordinateMath`.
public final class RealAXNode: AXNode {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }
    public func children() -> [any AXNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children.map(RealAXNode.init)
    }
    public func attributes() -> AXNodeAttributes {
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                     kAXPlaceholderValueAttribute, kAXValueAttribute, kAXPositionAttribute,
                     kAXSizeAttribute, kAXEnabledAttribute]
        let values = Self.copyMultiple(element, names)
        var actions: [String] = []
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success {
            actions = (actionNames as? [String]) ?? []
        }
        return AXNodeAttributes(
            role: values[kAXRoleAttribute] as? String,
            subrole: values[kAXSubroleAttribute] as? String,
            title: values[kAXTitleAttribute] as? String,
            description: values[kAXDescriptionAttribute] as? String,
            placeholder: values[kAXPlaceholderValueAttribute] as? String,
            value: values[kAXValueAttribute] as? String,
            frame: Self.frame(position: values[kAXPositionAttribute], size: values[kAXSizeAttribute]),
            isEnabled: values[kAXEnabledAttribute] as? Bool,
            actions: actions)
    }
    private static func copyMultiple(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray,
                                                           AXCopyMultipleAttributeOptions(rawValue: 0), &raw)
        guard error == .success, let items = raw as? [Any] else { return [:] }
        var values: [String: CFTypeRef] = [:]
        for (index, item) in items.enumerated() where index < names.count {
            values[names[index]] = item as AnyObject
        }
        return values
    }
    private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let position, let size, let origin = point(position), let dimensions = sizeOf(size) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    private static func point(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }
    private static func sizeOf(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}

public final class RealAXNodeFactory: AXNodeFactory {
    public init() {
        _ = AXTreeCrawler.installGlobalMessagingTimeout()
    }
    public func focusedWindow(of pid: pid_t) -> (any AXNode)? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return RealAXNode(value as! AXUIElement)
    }
    public func node(for element: AXUIElement) -> any AXNode {
        RealAXNode(element)
    }
}
