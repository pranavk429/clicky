import CoreGraphics
import Foundation
/// Global CoreGraphics rects (top-left of primary, y down) → panel-local
/// coordinates. SwiftUI in an NSHostingView uses top-left origin, so results
/// are directly usable by the ghost-cursor views.
public enum OverlayGeometry {
    public static func localRect(fromCGGlobal rect: CGRect, onScreen screen: CGRect) -> CGRect {
        let x = min(max(rect.origin.x - screen.origin.x, 0), max(screen.width, 0))
        let y = min(max(rect.origin.y - screen.origin.y, 0), max(screen.height, 0))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
    public static func localPoint(fromCGGlobal point: CGPoint, onScreen screen: CGRect) -> CGPoint {
        CGPoint(x: point.x - screen.origin.x, y: point.y - screen.origin.y)
    }

    /// Global CG frame (top-left of the primary, y down) for a small panel of
    /// `size` centered on a panel-local point of `screen`. Places the
    /// interactive confirmation-card panel exactly where the pure card layout
    /// (`OverlayLayout.cardCenter`) would draw the card in the full-screen
    /// panel.
    public static func globalFrame(centeredAtLocalPoint local: CGPoint,
                                   size: CGSize,
                                   onScreen screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + local.x - size.width / 2,
               y: screen.minY + local.y - size.height / 2,
               width: size.width,
               height: size.height)
    }

    /// Inverse of `CoordinateMath.cgFrame(fromAppKit:primaryHeight:)`:
    /// converts a global CG (top-left, y down) frame to the AppKit global frame
    /// (bottom-left, y up) that `NSWindow.setFrame(_:display:)` expects.
    public static func appKitFrame(fromCGGlobal frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
