import CoreGraphics
import Foundation
/// One attached display in both coordinate systems Clicky bridges.
/// `cgFrame`: top-left origin of the primary, y down (SCK, CGEvent, vision).
/// `appKitFrame`: bottom-left origin of the primary, y up (NSScreen).
public struct DisplayGeometry: Equatable, Sendable {
    public let id: UInt32
    public let cgFrame: CGRect
    public let appKitFrame: CGRect
    public let scaleFactor: CGFloat
    public var pixelSize: CGSize { CGSize(width: cgFrame.width * scaleFactor, height: cgFrame.height * scaleFactor) }
    public init(id: UInt32, cgFrame: CGRect, appKitFrame: CGRect, scaleFactor: CGFloat) {
        self.id = id; self.cgFrame = cgFrame; self.appKitFrame = appKitFrame; self.scaleFactor = scaleFactor
    }
}
/// The single home for every AppKit ↔ CoreGraphics ↔ normalized-vision
/// conversion (a y-flip or Retina bug here is the documented #2 time-sink).
public enum CoordinateMath {
    public static func cgPoint(fromAppKit p: CGPoint, primaryHeight: CGFloat) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    public static func appKitPoint(fromCG p: CGPoint, primaryHeight: CGFloat) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    public static func cgFrame(fromAppKit f: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: f.origin.x, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }
    public static func display(containing cgPoint: CGPoint, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        displays.first { $0.cgFrame.contains(cgPoint) }
    }
    public static func cgPoint(fromNormalized n: CGPoint, on d: DisplayGeometry) -> CGPoint {
        let x = min(max(n.x, 0), 1), y = min(max(n.y, 0), 1)
        return CGPoint(x: d.cgFrame.minX + x * d.cgFrame.width, y: d.cgFrame.minY + y * d.cgFrame.height)
    }
    public static func normalizedPoint(fromCG p: CGPoint, on d: DisplayGeometry) -> CGPoint? {
        guard d.cgFrame.width > 0, d.cgFrame.height > 0, d.cgFrame.contains(p) else { return nil }
        return CGPoint(x: (p.x - d.cgFrame.minX) / d.cgFrame.width, y: (p.y - d.cgFrame.minY) / d.cgFrame.height)
    }
}
