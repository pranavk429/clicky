import AppKit
import Combine
import SwiftUI

/// RGBA in sRGB (unit range) — a value type so the state → visual mapping is
/// deterministic and testable without a window server (spec §4.3).
struct OverlayColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let aiBlue = OverlayColor(red: 0.16, green: 0.52, blue: 1.00, alpha: 1)
    static let reviewAmber = OverlayColor(red: 1.00, green: 0.70, blue: 0.12, alpha: 1)
    static let confirmRed = OverlayColor(red: 1.00, green: 0.26, blue: 0.22, alpha: 1)
    static let stoppedGreen = OverlayColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)

    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// The four Ghost Cursor visual states (spec §4.3).
enum OverlayVisualState: String, Equatable, Sendable, CaseIterable {
    case moving   // blue pointer on a smooth Bézier trajectory
    case review   // amber bounding box around a reversible-action target
    case confirm  // pulsing red box + translucent pointer resting on the target
    case stopped  // green "Clicky stopped" banner
}

/// Pure state → visual mapping. Color, shape and motion never come from the model.
struct OverlayVisualStyle: Equatable, Sendable {
    let tint: OverlayColor
    let boxLineWidth: CGFloat
    let pulses: Bool
    let restsOnTarget: Bool
    let showsBanner: Bool

    static func style(for state: OverlayVisualState) -> OverlayVisualStyle {
        switch state {
        case .moving:
            return OverlayVisualStyle(tint: .aiBlue, boxLineWidth: 0, pulses: false, restsOnTarget: false, showsBanner: false)
        case .review:
            return OverlayVisualStyle(tint: .reviewAmber, boxLineWidth: 3, pulses: false, restsOnTarget: false, showsBanner: false)
        case .confirm:
            return OverlayVisualStyle(tint: .confirmRed, boxLineWidth: 4, pulses: true, restsOnTarget: true, showsBanner: false)
        case .stopped:
            return OverlayVisualStyle(tint: .stoppedGreen, boxLineWidth: 0, pulses: false, restsOnTarget: false, showsBanner: true)
        }
    }
}

/// Quadratic-Bézier pointer trajectory + cubic-Bézier (smoothstep) timing.
enum PointerTrajectory {
    /// Cubic Bézier timing curve with control values (0, 0, 1, 1):
    /// B(t) = 3t² − 2t³ — a symmetric ease-in-out.
    static func easedProgress(_ t: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Point on the quadratic Bézier `start → control → end` at `progress`.
    static func position(start: CGPoint, control: CGPoint, end: CGPoint, progress: CGFloat) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let m = 1 - t
        return CGPoint(x: m * m * start.x + 2 * m * t * control.x + t * t * end.x,
                       y: m * m * start.y + 2 * m * t * control.y + t * t * end.y)
    }

    /// Control point: the midpoint pushed `arc` points perpendicular to the
    /// travel direction, so the pointer dips instead of cutting straight.
    static func controlPoint(from start: CGPoint, to end: CGPoint, arc: CGFloat = 24) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else { return mid }
        return CGPoint(x: mid.x - dy / length * arc, y: mid.y + dx / length * arc)
    }
}

/// Panel-local placement for the confirmation card and the stopped banner.
enum OverlayLayout {
    static let cardSize = CGSize(width: 340, height: 104)
    static let margin: CGFloat = 12

    /// Card sits just below the target box, flips above when it would leave the
    /// panel, and clamps horizontally inside the panel.
    static func cardCenter(near rect: CGRect?, in size: CGSize) -> CGPoint {
        let anchor = rect ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        let below = anchor.maxY + margin + cardSize.height / 2
        let above = anchor.minY - margin - cardSize.height / 2
        let y = (below + cardSize.height / 2 <= size.height - margin) ? below : max(above, cardSize.height / 2 + margin)
        let minX = cardSize.width / 2 + margin
        let maxX = max(size.width - cardSize.width / 2 - margin, minX)
        return CGPoint(x: min(max(anchor.midX, minX), maxX), y: y)
    }

    /// Banner: top-center of the panel, clear of the menu bar.
    static func bannerCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: margin + 32)
    }
}
