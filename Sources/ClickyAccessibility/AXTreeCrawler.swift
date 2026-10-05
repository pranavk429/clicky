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
    public var frame: CGRect?
    public var isEnabled: Bool?
    public var actions: [String]

    public init(role: String? = nil, subrole: String? = nil, title: String? = nil, description: String? = nil,
                placeholder: String? = nil, frame: CGRect? = nil, isEnabled: Bool? = nil, actions: [String] = []) {
        self.role = role; self.subrole = subrole; self.title = title; self.description = description
        self.placeholder = placeholder; self.frame = frame; self.isEnabled = isEnabled; self.actions = actions
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

/// Focused-window flattener (spec §4.2/§4.5): BFS, depth ≤ 5 / ≤ 2000 nodes via
/// `CrawlerBudget`, one batched fetch per node. AX work stays on this actor, never `@MainActor`.
public actor AXTreeCrawler {
    public static let shared = AXTreeCrawler(source: RealAXNodeFactory())
    private let source: any AXNodeFactory

    public init(source: any AXNodeFactory) {
        self.source = source
    }
    /// Errata B2: set ONCE on the system-wide element ("globally for this process");
    /// per-element wrapping is NOT equivalent. `RealAXNodeFactory` calls this on init.
    @discardableResult
    public static func installGlobalMessagingTimeout() -> AXError {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), CrawlerBudget.interfaceTimeoutSeconds)
    }
    /// Crawl the app's focused window (PID path). Empty on AX failure — callers fall back.
    public func snapshot(focusedWindowOf pid: pid_t) -> [ElementSnapshot] {
        guard let root = source.focusedWindow(of: pid) else { return [] }
        return flatten(root)
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
    /// Pure projection (unit-tested via fakes); role-less nodes cannot be action targets, so they are dropped.
    static func makeSnapshot(attributes: AXNodeAttributes, element: AXUIElement) -> ElementSnapshot? {
        guard let role = attributes.role, !role.isEmpty else { return nil }
        return ElementSnapshot(
            element: element,
            key: CacheKey(role: role, subrole: attributes.subrole ?? "",
                          title: attributes.title ?? "", description: attributes.description ?? ""),
            frame: attributes.frame ?? .zero,
            isEnabled: attributes.isEnabled ?? true,
            isSecureField: ElementSnapshot.looksSecure(role: role, subrole: attributes.subrole,
                                                       title: attributes.title, placeholder: attributes.placeholder),
            actions: attributes.actions)
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
                     kAXPlaceholderValueAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute]
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
