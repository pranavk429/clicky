/// Demo subset of the Chunk 11 ghost-cursor overlay (plan Chunk 4.5, user-approved 2026-10-05).
/// Single main-screen panel, drawn shapes only; deliberately not unit-tested (no ClickyOverlay
/// test target yet — Chunk 11 must absorb or retire this file).
import AppKit

/// Drives the single borderless, click-through ghost-cursor panel for the demo.
///
/// The panel lives on the main screen, ignores every mouse event (it is set once
/// in `init` and never touched again), never becomes key, and draws every element
/// with `NSBezierPath`/`NSAttributedString` so no image assets are required.
@MainActor
public final class GhostCursorController {
    private let panel: NSPanel
    private let ghostView: GhostCursorView
    private let screenOrigin: CGPoint

    private var confirmationTimer: Timer?
    private var flashTimer: Timer?

    /// Builds the panel on the primary display (`NSScreen.screens[0]`), falling
    /// back to `NSScreen.main` and finally to a default frame when headless.
    public init() {
        let screen = NSScreen.screens.first ?? NSScreen.main
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let view = GhostCursorView(frame: CGRect(origin: .zero, size: screenFrame.size))
        view.autoresizingMask = [.width, .height]
        view.cursorPoint = CGPoint(x: screenFrame.width / 2, y: screenFrame.height / 2)

        let panel = NSPanel(contentRect: screenFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = view

        self.screenOrigin = screenFrame.origin
        self.ghostView = view
        self.panel = panel
    }

    /// Brings the panel forward without activating the app and repaints it.
    public func showOverlay() {
        panel.orderFrontRegardless()
        ghostView.needsDisplay = true
    }

    /// Hides the panel, stops every timer, and clears transient overlays.
    public func hideOverlay() {
        panel.orderOut(nil)
        invalidateTimers()
        ghostView.confirmationText = nil
        ghostView.confirmationPhase = 0
        ghostView.actionFlashText = nil
        ghostView.stoppedText = nil
        ghostView.needsDisplay = true
    }

    /// Sets the persistent status text in the top pill.
    public func setStatus(_ text: String) {
        ghostView.statusText = text
        ghostView.needsDisplay = true
    }

    /// Sets (or clears, with `nil`) the intent label drawn below-right of the cursor.
    public func setIntent(_ text: String?) {
        ghostView.intentText = text
        ghostView.needsDisplay = true
    }

    /// Animates the ghost pointer to an AppKit global screen point (bottom-left
    /// origin of the primary display, y up) and returns when the animation is done.
    /// Returns early if the surrounding task is cancelled; snaps when `duration <= 0`.
    public func moveCursor(to screenPoint: CGPoint, duration: TimeInterval) async {
        let target = localPoint(from: screenPoint)
        let start = ghostView.cursorPoint

        guard duration > 0 else {
            ghostView.cursorPoint = target
            ghostView.needsDisplay = true
            return
        }

        let clock = ContinuousClock()
        let startInstant = clock.now
        while true {
            if Task.isCancelled { return }
            let seconds = elapsedSeconds(since: startInstant, clock: clock)
            let progress = min(max(seconds / duration, 0), 1)
            let eased = GhostEasing.easeOutCubic(CGFloat(progress))
            ghostView.cursorPoint = CGPoint(x: start.x + (target.x - start.x) * eased,
                                            y: start.y + (target.y - start.y) * eased)
            ghostView.needsDisplay = true
            if progress >= 1 { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Shows the red pulsing confirmation gate around the cursor.
    public func showConfirmation(_ text: String) {
        ghostView.confirmationText = text
        ghostView.confirmationPhase = 0
        ghostView.needsDisplay = true
        confirmationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceConfirmationPulse() }
        }
        confirmationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Clears the confirmation gate and stops its pulse timer.
    public func dismissConfirmation() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        ghostView.confirmationText = nil
        ghostView.confirmationPhase = 0
        ghostView.needsDisplay = true
    }

    /// Shows a brief amber chip confirming an action, auto-cleared after ~1.0 s.
    public func flashAction(_ text: String) {
        ghostView.actionFlashText = text
        ghostView.needsDisplay = true
        flashTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ghostView.actionFlashText = nil
                self?.ghostView.needsDisplay = true
                self?.flashTimer = nil
            }
        }
        flashTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Shows the large green "stopped" banner until `hideOverlay()`.
    public func showStopped(_ reason: String) {
        ghostView.stoppedText = reason
        ghostView.needsDisplay = true
    }

    private func advanceConfirmationPulse() {
        guard ghostView.confirmationText != nil else { return }
        ghostView.confirmationPhase += CGFloat(0.05 / 1.2)
        if ghostView.confirmationPhase > 1 { ghostView.confirmationPhase -= 1 }
        ghostView.needsDisplay = true
    }

    private func invalidateTimers() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        flashTimer?.invalidate()
        flashTimer = nil
    }

    private func localPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - screenOrigin.x, y: screenPoint.y - screenOrigin.y)
    }

    private func elapsedSeconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Double {
        let components = start.duration(to: clock.now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Clamped cubic ease-out used by the ghost-cursor animation.
///
/// Deliberately **not** unit-tested: there is no ClickyOverlay test target yet.
/// Plan Chunk 11 will absorb or retire this whole file.
public enum GhostEasing {
    /// Returns `1 - (1 - t)^3` with `t` clamped to `0...1`.
    public static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let inverse = 1 - clamped
        return 1 - inverse * inverse * inverse
    }
}

/// Single non-flipped view that draws every ghost-cursor element in panel-local
/// coordinates. Being non-flipped (`isFlipped == false`, the AppKit default) keeps
/// panel-local y-up coordinates aligned directly with AppKit global screen points.
private final class GhostCursorView: NSView {
    var cursorPoint: CGPoint = .zero
    var intentText: String?
    var confirmationText: String?
    var confirmationPhase: CGFloat = 0
    var actionFlashText: String?
    var statusText: String?
    var stoppedText: String?

    private let chipFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private let statusFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private let stoppedFont = NSFont.systemFont(ofSize: 26, weight: .bold)

    private static let pointerPoints: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 0, y: -17),
        CGPoint(x: 4.6, y: -12),
        CGPoint(x: 7.2, y: -18.6),
        CGPoint(x: 10.2, y: -17.2),
        CGPoint(x: 7.6, y: -10.8),
        CGPoint(x: 12.8, y: -10.8)
    ]

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawStatus()
        drawGhostPointer()
        if let intentText { drawIntent(intentText) }
        if let confirmationText { drawConfirmation(confirmationText) }
        if let actionFlashText { drawActionFlash(actionFlashText) }
        if let stoppedText { drawStopped(stoppedText) }
    }

    private func drawGhostPointer() {
        let haloRect = CGRect(x: cursorPoint.x - 16, y: cursorPoint.y - 16, width: 32, height: 32)
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn: haloRect).fill()

        let points = GhostCursorView.pointerPoints
        let path = NSBezierPath()
        path.move(to: CGPoint(x: cursorPoint.x + points[0].x, y: cursorPoint.y + points[0].y))
        for point in points.dropFirst() {
            path.line(to: CGPoint(x: cursorPoint.x + point.x, y: cursorPoint.y + point.y))
        }
        path.close()
        NSColor.systemBlue.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }

    private func drawIntent(_ text: String) {
        let size = chipSize(text, font: chipFont, horizontalPadding: 10, verticalPadding: 6)
        let rect = CGRect(x: cursorPoint.x + 18,
                          y: cursorPoint.y - 44 - size.height,
                          width: size.width,
                          height: size.height)
        drawChip(text, in: rect, fill: .systemOrange, textColor: .black,
                 border: .white, borderWidth: 1, font: chipFont, cornerRadius: 8)
    }

    private func drawConfirmation(_ text: String) {
        let alpha = CGFloat(0.3 + 0.7 * sin(Double.pi * Double(confirmationPhase)))
        let ringRect = CGRect(x: cursorPoint.x - 28, y: cursorPoint.y - 28, width: 56, height: 56)
        let ring = NSBezierPath(ovalIn: ringRect)
        NSColor.systemRed.withAlphaComponent(alpha).setStroke()
        ring.lineWidth = 4
        ring.stroke()

        let size = chipSize(text, font: chipFont, horizontalPadding: 12, verticalPadding: 7)
        let rect = CGRect(x: cursorPoint.x + 18,
                          y: cursorPoint.y - 78 - size.height,
                          width: size.width,
                          height: size.height)
        drawChip(text, in: rect, fill: .systemRed, textColor: .white,
                 border: nil, borderWidth: 0, font: chipFont, cornerRadius: 8)
    }

    private func drawActionFlash(_ text: String) {
        let size = chipSize(text, font: chipFont, horizontalPadding: 10, verticalPadding: 6)
        let rect = CGRect(x: cursorPoint.x + 18,
                          y: cursorPoint.y - 78 - size.height,
                          width: size.width,
                          height: size.height)
        drawChip(text, in: rect, fill: .systemOrange, textColor: .black,
                 border: .white, borderWidth: 1, font: chipFont, cornerRadius: 8)
    }

    private func drawStatus() {
        guard let statusText, !statusText.isEmpty else { return }
        let size = chipSize(statusText, font: statusFont, horizontalPadding: 16, verticalPadding: 8)
        let rect = CGRect(x: bounds.midX - size.width / 2,
                          y: bounds.height - 40 - size.height / 2,
                          width: size.width,
                          height: size.height)
        drawChip(statusText, in: rect, fill: NSColor.black.withAlphaComponent(0.72),
                 textColor: .white, border: nil, borderWidth: 0, font: statusFont,
                 cornerRadius: size.height / 2)
    }

    private func drawStopped(_ text: String) {
        let size = chipSize(text, font: stoppedFont, horizontalPadding: 28, verticalPadding: 18)
        let rect = CGRect(x: bounds.midX - size.width / 2,
                          y: bounds.midY - size.height / 2,
                          width: size.width,
                          height: size.height)
        drawChip(text, in: rect, fill: .systemGreen, textColor: .white,
                 border: nil, borderWidth: 0, font: stoppedFont, cornerRadius: 16)
    }

    private func chipSize(_ text: String, font: NSFont,
                          horizontalPadding: CGFloat, verticalPadding: CGFloat) -> CGSize {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(textSize.width) + 2 * horizontalPadding,
                      height: ceil(textSize.height) + 2 * verticalPadding)
    }

    private func drawChip(_ text: String, in rect: CGRect, fill: NSColor, textColor: NSColor,
                          border: NSColor?, borderWidth: CGFloat, font: NSFont,
                          cornerRadius: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        fill.setFill()
        path.fill()
        if let border {
            border.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])
        let size = attributed.size()
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        attributed.draw(at: origin)
    }
}
