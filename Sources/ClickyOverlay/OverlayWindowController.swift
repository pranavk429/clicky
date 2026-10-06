import AppKit
import ClickyCore
import Foundation

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
