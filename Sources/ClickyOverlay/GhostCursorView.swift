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

/// Main-actor model shared by every panel's hosting view.
@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var presentations: [UInt32: PanelPresentation] = [:]
}

/// Panel content: renders the resolved presentation for one screen. Mouse
/// events never reach it (the panel ignores them); the accessibility tree does.
struct GhostCursorView: View {
    @ObservedObject var model: OverlayViewModel
    let screenID: UInt32
    let onCardAction: (OverlayCardAction) -> Void

    @State private var travelFrom: CGPoint = .zero
    @State private var travelTo: CGPoint = .zero
    @State private var travelProgress: CGFloat = 1

    private var presentation: PanelPresentation? { model.presentations[screenID] }

    private var movingPoint: CGPoint? {
        guard let presentation, presentation.state == .moving else { return nil }
        return presentation.localPoint
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                content(in: proxy.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: movingPoint) { oldValue, newValue in
            guard let newValue else { return }
            if oldValue == nil {
                travelFrom = newValue
                travelTo = newValue
            } else {
                // Start from the previous target; retargets mid-flight are rare
                // (tool calls arrive at human cadence).
                travelFrom = travelTo
                travelTo = newValue
                travelProgress = 0
                withAnimation(.linear(duration: 0.45)) { travelProgress = 1 }
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let presentation {
            let style = OverlayVisualStyle.style(for: presentation.state)
            switch presentation.state {
            case .moving:
                PointerGlyph(color: style.tint, opacity: 1)
                    .modifier(BezierTravelEffect(from: travelFrom, to: travelTo, progress: travelProgress))
            case .review:
                if let rect = presentation.localRect {
                    BoundingBoxView(color: style.tint, lineWidth: style.boxLineWidth, pulses: style.pulses)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel(presentation.accessibilityText ?? "Reversible action target")
                }
            case .confirm:
                if let rect = presentation.localRect {
                    BoundingBoxView(color: style.tint, lineWidth: style.boxLineWidth, pulses: style.pulses)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                if let point = presentation.localPoint {
                    PointerGlyph(color: style.tint, opacity: style.restsOnTarget ? 0.85 : 1)
                        .position(point)
                }
                if let prompt = presentation.accessibilityText {
                    ConfirmationCardView(prompt: prompt,
                                         onConfirm: { onCardAction(.confirm) },
                                         onCancel: { onCardAction(.cancel) })
                        .position(OverlayLayout.cardCenter(near: presentation.localRect, in: size))
                }
            case .stopped:
                if style.showsBanner, let message = presentation.accessibilityText {
                    StoppedBannerView(message: message, tint: style.tint)
                        .position(OverlayLayout.bannerCenter(in: size))
                }
            }
        }
    }
}

/// Custom animatable effect: translates the pointer along its Bézier path on
/// every frame while `progress` animates (the path is the quadratic Bézier;
/// the timing is the smoothstep cubic in `PointerTrajectory`).
struct BezierTravelEffect: GeometryEffect {
    var from: CGPoint
    var to: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let control = PointerTrajectory.controlPoint(from: from, to: to)
        let point = PointerTrajectory.position(start: from, control: control, end: to,
                                               progress: PointerTrajectory.easedProgress(progress))
        return ProjectionTransform(CGAffineTransform(translationX: point.x - size.width / 2,
                                                     y: point.y - size.height / 2))
    }
}

/// The ghost pointer glyph (blue while moving; translucent while resting).
struct PointerGlyph: View {
    let color: OverlayColor
    let opacity: Double

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(color.swiftUIColor)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

/// Amber review box / pulsing red confirmation box.
struct BoundingBoxView: View {
    let color: OverlayColor
    let lineWidth: CGFloat
    let pulses: Bool

    @State private var pulseDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(color.swiftUIColor, lineWidth: lineWidth)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.swiftUIColor.opacity(0.12)))
            .shadow(color: color.swiftUIColor.opacity(0.6), radius: 4)
            .opacity(pulses && pulseDimmed ? 0.45 : 1)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    pulseDimmed = true
                }
            }
    }
}

/// Accessible confirmation card (spec §4.3): VoiceOver reads the prompt; the
/// Confirm/Cancel pills are individual accessibility elements so VoiceOver and
/// switch control can reach and activate them. The panel is click-through, so
/// the accessibility tree — not the pointer — is the non-voice input path.
struct ConfirmationCardView: View {
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(prompt)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                CardButton(title: "Confirm", tint: .confirmRed, action: onConfirm)
                CardButton(title: "Cancel",
                           tint: OverlayColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1),
                           action: onCancel)
            }
        }
        .padding(14)
        .frame(width: OverlayLayout.cardSize.width)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirmation required")
        .accessibilityValue(prompt)
        .accessibilityHint("Say the confirmation phrase, or activate Confirm or Cancel with VoiceOver or switch control.")
    }
}

/// Mouse-inert pill; VoiceOver/switch activation presses it through AX.
struct CardButton: View {
    let title: String
    let tint: OverlayColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(tint.swiftUIColor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) action")
    }
}

/// Green "Clicky stopped" banner (kill switch or confirmation timeout).
struct StoppedBannerView: View {
    let message: String
    let tint: OverlayColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stop.circle.fill").font(.system(size: 15, weight: .bold))
            Text(message).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.swiftUIColor.opacity(0.94)))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
