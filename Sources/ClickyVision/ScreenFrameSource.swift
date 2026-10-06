import AppKit
import CoreGraphics
import CoreText
import Foundation
import ScreenCaptureKit

/// A single on-demand screen frame for the vision fallback. Frames are held in
/// memory only and are never written to disk.
public struct ScreenFrame: Sendable {
    public let jpeg: Data
    public let pixelSize: CGSize
    /// The captured window/display area in global display points (top-left
    /// origin, y down). Frame pixel coordinates map back to the screen through
    /// this rect: `screen = captureRect.origin + pixel * captureRect.size / pixelSize`.
    public let captureRect: CGRect
    /// Cursor position in the captured image's coordinate space (origin
    /// top-left, y down); `nil` when the cursor was outside the captured area
    /// (or the marker was disabled and no position could be resolved).
    public let cursorPoint: CGPoint?

    public init(jpeg: Data, pixelSize: CGSize, captureRect: CGRect, cursorPoint: CGPoint?) {
        self.jpeg = jpeg
        self.pixelSize = pixelSize
        self.captureRect = captureRect
        self.cursorPoint = cursorPoint
    }
}

public enum ScreenFrameError: Error, Equatable {
    case permissionDenied
    case noWindow
    case captureFailed(String)
}

/// Captures one frontmost-window frame on demand using ScreenCaptureKit.
///
/// Output policy is owned by `FramePolicy`: single frames only, downscaled to
/// fit `FramePolicy.maxFrameSize`, JPEG at `FramePolicy.jpegQuality`, never
/// written to disk. All coordinate conversion happens in-memory.
public final class ScreenFrameSource: @unchecked Sendable {
    /// CGWindowIDs to exclude from display captures — Clicky's own overlay
    /// panels (ghost cursor, review box, confirmation card) must never be baked
    /// into frames sent to the vision model (errata B11). Read at capture time
    /// so panels created after this source is built are still excluded;
    /// defaults to excluding nothing.
    public var excludedWindowNumbers: @Sendable () async -> [CGWindowID]

    public init(excludedWindowNumbers: @escaping @Sendable () async -> [CGWindowID] = { [] }) {
        self.excludedWindowNumbers = excludedWindowNumbers
    }

    /// Whether this process currently holds Screen Recording permission.
    public static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Captures the frontmost app's on-screen window (largest layer-0 window),
    /// falling back to the main display when the app has no shareable window.
    ///
    /// - Parameters:
    ///   - maxSize: upper bound for the encoded frame; the source is only ever
    ///     downscaled, never enlarged.
    ///   - quality: JPEG compression factor (`0...1`).
    ///   - includeCursorMarker: when `true`, composites a red dot at the mouse
    ///     position before encoding. `ScreenFrame.cursorPoint` is reported
    ///     whenever the cursor is inside the captured area, regardless of the
    ///     marker flag.
    ///   - grid: when set, composites a labeled `cols × rows` grid (cell labels
    ///     are a column letter + row number, e.g. "C5") onto the frame before
    ///     JPEG encoding. In-memory only, like the rest of the frame; `nil`
    ///     keeps the previous behavior exactly.
    public func captureFrontmostWindow(maxSize: CGSize = FramePolicy.maxFrameSize,
                                       quality: CGFloat = FramePolicy.jpegQuality,
                                       includeCursorMarker: Bool = true,
                                       grid: (cols: Int, rows: Int)? = nil) async throws -> ScreenFrame {
        // Check permission before touching ScreenCaptureKit so callers get a
        // deterministic error instead of an SCK-specific one.
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenFrameError.permissionDenied
        }

        let target = try await resolveCaptureTarget()
        let fitted = FramePolicy.fitSize(for: target.contentRect.size, into: maxSize)
        guard fitted.width >= 1, fitted.height >= 1 else {
            throw ScreenFrameError.captureFailed("maxSize has no usable area")
        }

        // ScreenCaptureKit scales the capture into the configured pixel size,
        // so the downscale happens in the capture pipeline (single resample).
        // `showsCursor = false`: the OS pointer is not baked in; we composite
        // our own marker so the reported cursor point matches the pixels.
        let configuration = SCStreamConfiguration()
        configuration.width = Int(fitted.width)
        configuration.height = Int(fitted.height)
        configuration.showsCursor = false

        let captured: CGImage
        do {
            captured = try await SCScreenshotManager.captureImage(contentFilter: target.filter,
                                                                  configuration: configuration)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw ScreenFrameError.permissionDenied
        } catch {
            throw ScreenFrameError.captureFailed("screenshot failed: \(error.localizedDescription)")
        }

        // Cursor resolution, chosen coordinate space:
        // `CGEvent(source: nil)?.location` is in global display coordinates
        // (origin top-left of the main display, y down) — the *same* space as
        // `SCWindow.frame` / `SCContentFilter.contentRect`, so no flip is
        // needed here. (`NSEvent.mouseLocation` uses a bottom-left origin and
        // is deliberately avoided; mixing the two is the classic off-by-screen
        // -height bug.) The only y-flip happens when drawing into a CGContext,
        // whose user space is bottom-left origin.
        var cursorPoint: CGPoint?
        var cursorImagePoint: CGPoint?
        if let global = CGEvent(source: nil)?.location, target.contentRect.contains(global) {
            let relativeX = (global.x - target.contentRect.minX) / target.contentRect.width
            let relativeY = (global.y - target.contentRect.minY) / target.contentRect.height
            let point = CGPoint(x: relativeX * CGFloat(captured.width),
                                y: relativeY * CGFloat(captured.height))
            cursorPoint = point
            cursorImagePoint = point
        }

        var composited: CGImage = captured
        if includeCursorMarker, let point = cursorImagePoint {
            composited = try compositeCursorMarker(on: composited, at: point)
        }
        if let grid {
            composited = try compositeGrid(on: composited, cols: grid.cols, rows: grid.rows)
        }

        guard let jpeg = NSBitmapImageRep(cgImage: composited).representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw ScreenFrameError.captureFailed("JPEG encoding failed")
        }

        return ScreenFrame(jpeg: jpeg,
                           pixelSize: CGSize(width: composited.width, height: composited.height),
                           captureRect: target.contentRect,
                           cursorPoint: cursorPoint)
    }

    // MARK: - Capture target

    private struct CaptureTarget {
        let filter: SCContentFilter
        /// Area covered by the capture, in global display points (top-left origin).
        let contentRect: CGRect
    }

    private func resolveCaptureTarget() async throws -> CaptureTarget {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw ScreenFrameError.permissionDenied
        } catch {
            throw ScreenFrameError.captureFailed("shareable content unavailable: \(error.localizedDescription)")
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Layer 0 = normal windows. Pick the largest as a deterministic stand-in
        // for the frontmost one (SCK exposes no z-order). Windows with an empty
        // frame are decorative or zero-sized; skip them.
        let window = content.windows
            .filter { $0.windowLayer == 0 && $0.owningApplication?.processID == frontmostPID }
            .filter { $0.frame.width >= 1 && $0.frame.height >= 1 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }

        if let window {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let rect = filter.contentRect.isEmpty ? window.frame : filter.contentRect
            guard rect.width >= 1, rect.height >= 1 else {
                throw ScreenFrameError.captureFailed("frontmost window has an empty frame")
            }
            return CaptureTarget(filter: filter, contentRect: rect)
        }

        // Fallback: the frontmost app has no shareable window (menu-bar apps,
        // Finder desktop, etc.) — capture the main display instead. Clicky's
        // own overlay panels are excluded by CGWindowID (errata B11) so the
        // ghost cursor and confirmation card never reach the vision model; when
        // no requested id matches, this stays the previous
        // `excludingWindows: []` behavior.
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw ScreenFrameError.noWindow
        }
        let excludedNumbers = Set(Self.windowsToExclude(
            windowNumbers: content.windows.map(\.windowID),
            excluding: await excludedWindowNumbers()))
        let filter = SCContentFilter(display: display,
                                     excludingWindows: content.windows.filter { excludedNumbers.contains($0.windowID) })
        let rect = filter.contentRect.isEmpty ? CGDisplayBounds(display.displayID) : filter.contentRect
        guard rect.width >= 1, rect.height >= 1 else {
            throw ScreenFrameError.captureFailed("display has no usable bounds")
        }
        return CaptureTarget(filter: filter, contentRect: rect)
    }

    /// The subset of `windowNumbers` that appears in `excluding` — the
    /// CGWindowIDs the display fallback hands to
    /// `SCContentFilter(display:excludingWindows:)`. Pure so the selection is
    /// unit-testable without ScreenCaptureKit; matching is by exact
    /// CGWindowID, never by title or frame.
    static func windowsToExclude(windowNumbers: [CGWindowID],
                                 excluding excluded: [CGWindowID]) -> [CGWindowID] {
        let exclusions = Set(excluded)
        return windowNumbers.filter { exclusions.contains($0) }
    }

    // MARK: - Marker compositing

    /// Draws a ~12 px red dot at `imagePoint` (image coordinates: top-left
    /// origin, y down) and flattens the result into a new image.
    private func compositeCursorMarker(on image: CGImage, at imagePoint: CGPoint) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            throw ScreenFrameError.captureFailed("unable to create compositing context")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext user space is bottom-left origin (y up), so flip y once:
        // image y = 0 (top) becomes user-space y = height.
        let radius: CGFloat = 6 // 12 px diameter at image scale
        let drawY = CGFloat(height) - imagePoint.y
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: imagePoint.x - radius,
                                       y: drawY - radius,
                                       width: radius * 2,
                                       height: radius * 2))

        guard let composited = context.makeImage() else {
            throw ScreenFrameError.captureFailed("unable to composite cursor marker")
        }
        return composited
    }

    // MARK: - Grid compositing

    /// Draws a labeled `cols × rows` grid onto `image` and flattens the result.
    /// Cell labels are column letter + row number ("A1" is top-left; 12×8 spans
    /// "A1"–"L8"). Lines are a thin semi-transparent double stroke (dark
    /// underlay, light overlay) so they stay readable on any content; each label
    /// sits in its cell's top-left corner.
    private func compositeGrid(on image: CGImage, cols: Int, rows: Int) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard cols >= 1, cols <= 26, rows >= 1, rows <= 99, width >= 1, height >= 1 else {
            throw ScreenFrameError.captureFailed("invalid grid dimensions")
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            throw ScreenFrameError.captureFailed("unable to create grid compositing context")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Image coordinates are top-left origin, y down; CGContext user space is
        // bottom-left, so flip once and use image coordinates for all cell math.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let cellWidth = CGFloat(width) / CGFloat(cols)
        let cellHeight = CGFloat(height) / CGFloat(rows)

        // Cell boundaries: internal lines plus the outer border.
        func strokeGrid(lineWidth: CGFloat, color: CGColor) {
            context.setLineWidth(lineWidth)
            context.setStrokeColor(color)
            context.beginPath()
            for column in 0...cols {
                let x = CGFloat(column) * cellWidth
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: CGFloat(height)))
            }
            for row in 0...rows {
                let y = CGFloat(row) * cellHeight
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: CGFloat(width), y: y))
            }
            context.strokePath()
        }
        strokeGrid(lineWidth: 3, color: CGColor(gray: 0, alpha: 0.30))
        strokeGrid(lineWidth: 1, color: CGColor(gray: 1, alpha: 0.70))

        // Labels, top-left corner of each cell. CoreText draws straight into the
        // CGContext (thread-safe); the flipped context needs a flipped text
        // matrix so glyphs render upright, and the baseline sits one ascent
        // below the cell's top edge plus the padding.
        let fontSize = max(9, min(14, min(cellWidth, cellHeight) * 0.16))
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let ascent = CTFontGetAscent(font)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.95),
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(gray: 0, alpha: 0.85),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -2.0,
        ]
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let padding: CGFloat = 3
        for row in 0..<rows {
            for column in 0..<cols {
                let label = "\(Self.gridColumnLabel(column))\(row + 1)"
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: label, attributes: attributes))
                context.textPosition = CGPoint(x: CGFloat(column) * cellWidth + padding,
                                               y: CGFloat(row) * cellHeight + padding + ascent)
                CTLineDraw(line, context)
            }
        }

        guard let composited = context.makeImage() else {
            throw ScreenFrameError.captureFailed("unable to composite grid")
        }
        return composited
    }

    /// 0-based column index → label letter ("A"…"Z"); `nil` for out-of-range.
    private static func gridColumnLabel(_ index: Int) -> String {
        guard index >= 0, index < 26, let scalar = UnicodeScalar(65 + index) else { return "?" }
        return String(Character(scalar))
    }
}
