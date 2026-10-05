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
}
