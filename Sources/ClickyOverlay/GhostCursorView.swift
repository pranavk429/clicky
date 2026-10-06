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

/// Pure activity → companion visual mapping. Like `OverlayVisualStyle`, the
/// model never chooses color or motion — each visible activity has exactly one
/// motion cue (Task T-OVERLAY).
struct CompanionVisualStyle: Equatable, Sendable {
    let tint: OverlayColor
    let showsWaveform: Bool
    let showsSpinner: Bool
    let pulsesRing: Bool

    var isVisible: Bool { tint.alpha > 0 }

    static func style(for activity: CompanionActivity) -> CompanionVisualStyle {
        switch activity {
        case .hidden:
            return CompanionVisualStyle(tint: OverlayColor(red: 0, green: 0, blue: 0, alpha: 0),
                                        showsWaveform: false, showsSpinner: false, pulsesRing: false)
        case .listening:
            return CompanionVisualStyle(tint: .aiBlue, showsWaveform: true, showsSpinner: false, pulsesRing: false)
        case .thinking:
            return CompanionVisualStyle(tint: .reviewAmber, showsWaveform: false, showsSpinner: true, pulsesRing: false)
        case .speaking:
            return CompanionVisualStyle(tint: .stoppedGreen, showsWaveform: false, showsSpinner: false, pulsesRing: true)
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

/// Panel-local placement for the confirmation card, the stopped banner and the
/// ambient cursor companion.
enum OverlayLayout {
    static let cardSize = CGSize(width: 340, height: 104)
    static let margin: CGFloat = 12

    /// The dedicated interactive card panel is the card plus a margin on every
    /// side, so the card (and its soft edge) is never clipped by the window.
    static let cardPanelSize = CGSize(width: cardSize.width + 2 * margin,
                                      height: cardSize.height + 2 * margin)

    /// Panel size for a measured card: the card plus a margin on every side,
    /// never smaller than the nominal `cardPanelSize`. Long prompts grow the
    /// panel instead of clipping; the card stays centered, so the placement
    /// math (`cardCenter` → `OverlayGeometry.globalFrame`) is unchanged.
    static func cardPanelSize(fittingCard size: CGSize) -> CGSize {
        CGSize(width: max(cardPanelSize.width, size.width + 2 * margin),
               height: max(cardPanelSize.height, size.height + 2 * margin))
    }

    /// Companion offset from the pointer tip (down-right in top-left
    /// coordinates) so the buddy never covers the system pointer.
    static let companionOffset = CGPoint(x: 22, y: 26)

    /// Companion anchor: just off the pointer tip, clamped inside the panel so
    /// it never leaves the screen.
    static func companionCenter(near point: CGPoint, in size: CGSize) -> CGPoint {
        let maxX = max(size.width - margin, margin)
        let maxY = max(size.height - margin, margin)
        return CGPoint(x: min(max(point.x + companionOffset.x, margin), maxX),
                       y: min(max(point.y + companionOffset.y, margin), maxY))
    }

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
    /// Ambient companion state, driven by the session/model layer through
    /// `.clickyModelActivityChanged` (or the session-state fallback).
    @Published var companion: CompanionActivity = .hidden
    /// Panel-local companion anchor per screen (the screen under the pointer).
    @Published var companionPoints: [UInt32: CGPoint] = [:]
}

/// Panel content: renders the resolved presentation for one screen. Mouse
/// events never reach it (the full-screen panel ignores them); the
/// accessibility tree does. The confirmation card lives in its own small
/// interactive panel (`ConfirmationCardPanel`) so this glass wall stays 100%
/// click-through.
struct GhostCursorView: View {
    @ObservedObject var model: OverlayViewModel
    let screenID: UInt32

    @State private var travelFrom: CGPoint = .zero
    @State private var travelTo: CGPoint = .zero
    @State private var travelProgress: CGFloat = 1
    @State private var travelSeeded = false

    private var presentation: PanelPresentation? { model.presentations[screenID] }

    private var movingPoint: CGPoint? {
        guard let presentation, presentation.state == .moving else { return nil }
        return presentation.localPoint
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                // Companion first: the ghost pointer/box always draw above it,
                // so an active `.moving`/`.confirm` presentation is never
                // obstructed by the buddy (Task T-OVERLAY placement choice).
                companionLayer(in: proxy.size)
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
        // `.onChange` never fires for a view's initial value, so a moving
        // presentation already present on first appearance (the `present`
        // fallback path, a screen-parameter rebuild) would leave the endpoints
        // at `.zero` and anchor the pointer in the panel corner. Seed once from
        // the current point; later moves stay on the unchanged `.onChange` path.
        .onAppear {
            guard !travelSeeded, let point = movingPoint else { return }
            travelFrom = point
            travelTo = point
            travelSeeded = true
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
                // Bounding box + resting pointer only — the interactive card
                // is a separate small panel (OverlayWindowController.showCard).
                if let rect = presentation.localRect {
                    BoundingBoxView(color: style.tint, lineWidth: style.boxLineWidth, pulses: style.pulses)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                if let point = presentation.localPoint {
                    PointerGlyph(color: style.tint, opacity: style.restsOnTarget ? 0.85 : 1)
                        .position(point)
                }
            case .stopped:
                if style.showsBanner, let message = presentation.accessibilityText {
                    StoppedBannerView(message: message, tint: style.tint)
                        .position(OverlayLayout.bannerCenter(in: size))
                }
            }
        }
    }

    /// Ambient cursor buddy: follows the mouse with a spring while the model
    /// activity is non-hidden. Rendered beneath `content(in:)` so it can never
    /// obstruct the ghost pointer, and never hit-testable (the parent view
    /// disables hit testing wholesale).
    @ViewBuilder
    private func companionLayer(in size: CGSize) -> some View {
        if model.companion != .hidden, let point = model.companionPoints[screenID] {
            CompanionView(activity: model.companion,
                          tint: CompanionVisualStyle.style(for: model.companion).tint)
                .position(OverlayLayout.companionCenter(near: point, in: size))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: point)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.companion)
                .accessibilityHidden(true)   // decorative: never a VoiceOver stop
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

/// Ambient cursor companion (Task T-OVERLAY): a small buddy that trails the
/// pointer while the model is listening, thinking or speaking. Purely
/// decorative — it never accepts mouse events (the parent view disables hit
/// testing wholesale).
struct CompanionView: View {
    let activity: CompanionActivity
    let tint: OverlayColor

    var body: some View {
        switch activity {
        case .hidden:
            EmptyView()
        case .listening:
            ListeningBuddyView(tint: tint)
        case .thinking:
            ThinkingBuddyView(tint: tint)
        case .speaking:
            SpeakingBuddyView(tint: tint)
        }
    }
}

/// Shared circular buddy body with a soft glow.
private struct BuddyShell<Content: View>: View {
    let tint: OverlayColor
    let content: Content

    init(tint: OverlayColor, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.78))
            Circle().stroke(tint.swiftUIColor.opacity(0.9), lineWidth: 1.5)
            content
        }
        .frame(width: 30, height: 30)
        .shadow(color: tint.swiftUIColor.opacity(0.7), radius: 6)
    }
}

/// `.listening`: glowing buddy with looping waveform bars.
struct ListeningBuddyView: View {
    let tint: OverlayColor

    @State private var animating = false
    private static let barHeights: [CGFloat] = [7, 13, 9, 15]

    var body: some View {
        BuddyShell(tint: tint) {
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<Self.barHeights.count, id: \.self) { index in
                    Capsule()
                        .fill(tint.swiftUIColor)
                        .frame(width: 2.5, height: animating ? Self.barHeights[index] : 4)
                        .animation(.easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.09),
                                   value: animating)
                }
            }
        }
        .onAppear { animating = true }
    }
}

/// `.thinking`: buddy with a rotating arc while the model works.
struct ThinkingBuddyView: View {
    let tint: OverlayColor

    @State private var spinning = false

    var body: some View {
        BuddyShell(tint: tint) {
            Circle()
                .trim(from: 0.05, to: 0.72)
                .stroke(tint.swiftUIColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
        }
        .onAppear { spinning = true }
    }
}

/// `.speaking`: buddy with a gentle pulsing ring while model audio plays.
struct SpeakingBuddyView: View {
    let tint: OverlayColor

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.swiftUIColor.opacity(0.85), lineWidth: 2)
                .frame(width: 30, height: 30)
                .scaleEffect(pulsing ? 1.55 : 1)
                .opacity(pulsing ? 0 : 0.9)
                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulsing)
            BuddyShell(tint: tint) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.swiftUIColor)
            }
        }
        .onAppear { pulsing = true }
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
/// switch control can reach and activate them. Hosted by the dedicated small
/// interactive panel (`ConfirmationCardPanel`), so the pills also respond to a
/// single mouse click there while every full-screen panel stays click-through.
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

/// Pill button: pressed by mouse in the card panel, or by VoiceOver/switch
/// activation through the accessibility tree.
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
