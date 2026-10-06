import AppKit
import ClickyCore
import Foundation
import SwiftUI

/// Commands the rest of the app sends to the overlay — the interface contract
/// for the integration chunks (spec §4.3). Geometry is global CoreGraphics:
/// top-left origin of the primary display, y grows downward — the same space
/// as AX frames, CGEvent points and ScreenCaptureKit. Call on the main actor.
public enum OverlayCommand: Equatable, Sendable {
    case moving(to: CGPoint)
    case review(rect: CGRect, label: String?)
    case confirm(rect: CGRect, point: CGPoint, prompt: String)
    case stopped(reason: String)
    case hidden

    var visualState: OverlayVisualState? {
        switch self {
        case .moving: return .moving
        case .review: return .review
        case .confirm: return .confirm
        case .stopped: return .stopped
        case .hidden: return nil
        }
    }
}

/// Accessibility activation of the confirmation card (VoiceOver / switch
/// control). The integration layer maps these onto the pending-action gate;
/// nothing here executes hardware input by itself.
public enum OverlayCardAction: Equatable, Sendable {
    case confirm
    case cancel
}

/// One panel's resolved drawing instructions, already converted to
/// panel-local (top-left origin) coordinates.
struct PanelPresentation: Equatable, Sendable {
    let screenID: UInt32
    let state: OverlayVisualState
    let localPoint: CGPoint?
    let localRect: CGRect?
    let accessibilityText: String?
}

/// Pure placement: global CG command → per-panel local presentations.
enum OverlayPlacementResolver {
    static func resolve(_ command: OverlayCommand,
                        screens: [DisplayGeometry],
                        lastActiveScreenID: UInt32?) -> [PanelPresentation] {
        switch command {
        case .hidden:
            return []
        case .moving(let point):
            guard let screen = target(containing: point, in: screens) else { return [] }
            return [PanelPresentation(screenID: screen.id, state: .moving,
                                      localPoint: clamp(OverlayGeometry.localPoint(fromCGGlobal: point, onScreen: screen.cgFrame),
                                                        into: screen.cgFrame.size),
                                      localRect: nil, accessibilityText: nil)]
        case .review(let rect, let label):
            guard let screen = target(containing: center(of: rect), in: screens) else { return [] }
            return [PanelPresentation(screenID: screen.id, state: .review, localPoint: nil,
                                      localRect: OverlayGeometry.localRect(fromCGGlobal: rect, onScreen: screen.cgFrame),
                                      accessibilityText: label)]
        case .confirm(let rect, let point, let prompt):
            guard let screen = target(containing: center(of: rect), in: screens) else { return [] }
            return [PanelPresentation(screenID: screen.id, state: .confirm,
                                      localPoint: clamp(OverlayGeometry.localPoint(fromCGGlobal: point, onScreen: screen.cgFrame),
                                                        into: screen.cgFrame.size),
                                      localRect: OverlayGeometry.localRect(fromCGGlobal: rect, onScreen: screen.cgFrame),
                                      accessibilityText: prompt)]
        case .stopped(let reason):
            guard let screen = stopScreen(in: screens, lastActiveScreenID: lastActiveScreenID) else { return [] }
            return [PanelPresentation(screenID: screen.id, state: .stopped, localPoint: nil, localRect: nil,
                                      accessibilityText: "Clicky stopped. \(reason)")]
        }
    }

    private static func center(of rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// Screen containing `point`; when off-screen, the nearest screen so the
    /// pointer still appears where the user is looking.
    private static func target(containing point: CGPoint, in screens: [DisplayGeometry]) -> DisplayGeometry? {
        if let hit = CoordinateMath.display(containing: point, in: screens) { return hit }
        return screens.min {
            distanceSquared(from: $0.cgFrame, to: point) < distanceSquared(from: $1.cgFrame, to: point)
        }
    }

    private static func distanceSquared(from frame: CGRect, to point: CGPoint) -> CGFloat {
        let dx = max(frame.minX - point.x, max(0, point.x - frame.maxX))
        let dy = max(frame.minY - point.y, max(0, point.y - frame.maxY))
        return dx * dx + dy * dy
    }

    private static func clamp(_ point: CGPoint, into size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), max(size.width, 0)),
                y: min(max(point.y, 0), max(size.height, 0)))
    }

    /// Stopped banner: the screen that was last active, else the menu-bar
    /// screen (first in `NSScreen.screens` order).
    private static func stopScreen(in screens: [DisplayGeometry], lastActiveScreenID: UInt32?) -> DisplayGeometry? {
        if let lastActiveScreenID, let screen = screens.first(where: { $0.id == lastActiveScreenID }) { return screen }
        return screens.first
    }
}

/// One borderless panel per screen. The glass-wall invariant (spec §4.3;
/// report 03 time-sink #5): `ignoresMouseEvents` is set ONCE here, in `init`,
/// and no other line in this module may touch it — flipping it mid-run makes
/// every click on the Mac land on the overlay. `canBecomeKey`/`canBecomeMain`
/// are permanently false so the overlay never steals focus.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true          // set once — the glass wall
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none                // keeps legacy captures clean too
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the per-screen panels. Spec §4.3: `start()` pre-creates them at launch
/// and rebuilds on display changes (lazy creation adds 50–200 ms and breaks the
/// execution-leg budget); the first `present` is a documented safety net for a
/// missing launch call only — a no-op once the panels exist.
@MainActor
public final class OverlayWindowController {
    public static let shared = OverlayWindowController()

    /// CGWindowIDs of the live panels. The vision path reads this at capture
    /// time and excludes the panels from ScreenCaptureKit (errata B11).
    public private(set) var panelWindowIDs: [CGWindowID] = []

    /// Wired by the integration layer to the pending-action gate.
    public var onCardAction: ((OverlayCardAction) -> Void)?

    private let model = OverlayViewModel()
    private var panels: [PanelRecord] = []
    private var lastActiveScreenID: UInt32?
    private var screenObserver: NSObjectProtocol?

    private struct PanelRecord {
        let geometry: DisplayGeometry
        let panel: OverlayPanel
    }

    private init() {}

    /// Creates/orders the panels and starts observing screen changes. Call once
    /// at app launch (spec §4.3 pre-creation). Idempotent: the first `present`
    /// also starts defensively when the integration missed this call.
    public func start() {
        guard panels.isEmpty else { return }
        rebuildPanels()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.rebuildPanels() }
            }
        }
    }

    public func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for record in panels { record.panel.orderOut(nil) }
        panels = []
        panelWindowIDs = []
        lastActiveScreenID = nil
        model.presentations = [:]
    }

    /// Interface contract for the integration chunks: present each state at a
    /// global CG point/rect; `.hidden` clears every panel. Starts the overlay
    /// if `start()` was never called (no-op on the demo path).
    public func present(_ command: OverlayCommand) {
        start()
        let presentations = OverlayPlacementResolver.resolve(command,
                                                             screens: panels.map(\.geometry),
                                                             lastActiveScreenID: lastActiveScreenID)
        model.presentations = Dictionary(presentations.map { ($0.screenID, $0) },
                                         uniquingKeysWith: { _, latest in latest })
        guard let first = presentations.first else { return }
        switch first.state {
        case .confirm:
            announce(first.accessibilityText, onScreen: first.screenID)
            lastActiveScreenID = first.screenID
        case .stopped:
            announce(first.accessibilityText, onScreen: first.screenID)
        case .moving, .review:
            lastActiveScreenID = first.screenID
        }
    }

    /// Integration convenience API — the exact entry points the Chunk 13
    /// `OverlayAdapter` calls; all funnel into `present(_:)`.
    public func presentMoving(at point: CGPoint) { present(.moving(to: point)) }
    public func presentReview(rect: CGRect, label: String) { present(.review(rect: rect, label: label)) }
    public func presentConfirmation(rect: CGRect, label: String) {
        present(.confirm(rect: rect, point: CGPoint(x: rect.midX, y: rect.midY), prompt: label))
    }
    public func presentStopped(reason: String) { present(.stopped(reason: reason)) }

    private func rebuildPanels() {
        for record in panels { record.panel.orderOut(nil) }
        model.presentations = [:]
        let primaryHeight = Self.primaryHeight()
        panels = NSScreen.screens.map { screen in
            let geometry = DisplayGeometry.from(screen: screen, primaryHeight: primaryHeight)
            let panel = OverlayPanel(screen: screen)
            let hosting = NSHostingView(rootView: GhostCursorView(
                model: model,
                screenID: geometry.id,
                onCardAction: { [weak self] action in self?.onCardAction?(action) }))
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hosting
            panel.orderFrontRegardless()
            return PanelRecord(geometry: geometry, panel: panel)
        }
        panelWindowIDs = panels.map { CGWindowID($0.panel.windowNumber) }
    }

    /// VoiceOver announcement so the prompt reaches users even though the panel
    /// never becomes key (spec §4.3: the card is VoiceOver-readable).
    private func announce(_ text: String?, onScreen screenID: UInt32) {
        guard let text,
              let element = panels.first(where: { $0.geometry.id == screenID })?.panel.contentView else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// AppKit → CG flip anchor: the primary screen (origin {0,0}) supplies the
    /// height for `CoordinateMath.cgFrame(fromAppKit:primaryHeight:)`.
    private static func primaryHeight() -> CGFloat {
        (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }
}

extension DisplayGeometry {
    /// Bridges an `NSScreen` into the coordinate model shared with AX, CGEvent
    /// and ScreenCaptureKit. `NSScreenNumber` is the `CGDirectDisplayID`.
    static func from(screen: NSScreen, primaryHeight: CGFloat) -> DisplayGeometry {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return DisplayGeometry(id: number?.uint32Value ?? 0,
                               cgFrame: CoordinateMath.cgFrame(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                               appKitFrame: screen.frame,
                               scaleFactor: screen.backingScaleFactor)
    }
}
