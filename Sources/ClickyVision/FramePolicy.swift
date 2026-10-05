import CoreGraphics
import Foundation
/// Policy for the on-demand single-frame vision fallback (never continuous
/// streaming; frames are downscaled and never written to disk).
public enum FramePolicy {
    public static let maxFrameSize = CGSize(width: 1024, height: 768)
    public static let jpegQuality: CGFloat = 0.7
    public static let maxFramesPerSecond = 1
    public static func fitSize(for source: CGSize, into maximum: CGSize = FramePolicy.maxFrameSize) -> CGSize {
        guard source.width > 0, source.height > 0, maximum.width > 0, maximum.height > 0 else { return .zero }
        let scale = min(maximum.width / source.width, maximum.height / source.height, 1.0)
        return CGSize(width: (source.width * scale).rounded(.down), height: (source.height * scale).rounded(.down))
    }
}
