import AppKit
import ClickyCore
import Foundation
import SwiftUI

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

/// Activation of the confirmation card — a mouse click in the card panel, or
/// VoiceOver / switch-control activation through the accessibility tree. The
/// integration layer maps these onto the pending-action gate; nothing here
/// executes hardware input by itself.
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

/// One borderless panel per screen. The glass-wall invariant (spec §4.3;
/// report 03 time-sink #5): `ignoresMouseEvents` is set ONCE here, in `init`,
/// and no other line in this module may touch it — flipping it mid-run makes
/// every click on the Mac land on the overlay. The ONLY interactive overlay
/// surface is the separate `ConfirmationCardPanel`. `canBecomeKey`/
/// `canBecomeMain` are permanently false so the overlay never steals focus.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true          // set once — the glass wall
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none                // keeps legacy captures clean too
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Small interactive panel that hosts the confirmation card. This is the only
/// Clicky overlay window that accepts mouse events; the full-screen
/// `OverlayPanel`s stay a pure glass wall. It is `.nonactivatingPanel`, so
/// clicking Confirm/Cancel never activates Clicky, and `becomesKeyOnlyIfNeeded`
/// means key status is granted only when a control needs it (the buttons do
/// not) — `showCard` never calls `makeKey`. Key status is allowed at all so
/// button tracking works reliably; `CardHostingView.acceptsFirstMouse` lets the
/// very first click land even while the panel is not key.
final class ConfirmationCardPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none                // keeps legacy captures clean too
        ignoresMouseEvents = false         // the one interactive overlay surface
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first mouse click even when its panel is not
/// key, so one click on Confirm/Cancel acts immediately instead of being
/// consumed to make the window key.
final class CardHostingView: NSHostingView<ConfirmationCardView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the per-screen panels. Spec §4.3: `start()` pre-creates them at launch
/// and rebuilds on display changes (lazy creation adds 50–200 ms and breaks the
/// execution-leg budget); the first `present` is a documented safety net for a
/// missing launch call only — a no-op once the panels exist.
@MainActor
public final class OverlayWindowController {
    public static let shared = OverlayWindowController()

    /// CGWindowIDs of EVERY live Clicky overlay window — the full-screen panels
    /// plus the confirmation-card panel while it exists. The vision path reads
    /// this at capture time and excludes these windows from ScreenCaptureKit
    /// (errata B11). Refreshed whenever panels are created and whenever the
    /// card panel is shown or dismissed.
    public private(set) var panelWindowIDs: [CGWindowID] = []

    /// Wired by the integration layer to the pending-action gate.
    public var onCardAction: ((OverlayCardAction) -> Void)?

    private let model = OverlayViewModel()
    private var panels: [PanelRecord] = []
    private var lastActiveScreenID: UInt32?
    /// The last `.confirm` command, kept so a display change can re-resolve it
    /// against the new geometry (the card must not vanish from a pending gate).
    private var pendingConfirmation: OverlayCommand?
    private var primaryHeight: CGFloat = 0
    private var screenObserver: NSObjectProtocol?
    private var activityObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    private var cardPanel: ConfirmationCardPanel?
    private var cardHostingView: CardHostingView?
    private var companionTimer: Timer?
    private var companionPolicy = CompanionTrackingPolicy()
    /// Teardown guard: observer callbacks enqueue main-actor work that can run
    /// after `stop()`. Deferred work checks this so it cannot resurrect panels
    /// or restart the companion timer once torn down.
    private var isStopped = false

    /// Canonical constant for this notification currently lives in the app
    /// target (`AppState`); `ClickyOverlay` depends only on `ClickyCore`, so it
    /// observes the raw name — `NotificationCenter` matches by name value.
    private static let sessionStateNotification = Notification.Name("clickySessionStateChanged")

    private struct PanelRecord {
        let geometry: DisplayGeometry
        let panel: OverlayPanel
    }

    private init() {}

    /// Creates/orders the panels, starts observing screen changes, and wires
    /// the ambient-companion activity signals. Call once at app launch
    /// (spec §4.3 pre-creation). Idempotent: the first `present` also starts
    /// defensively when the integration missed this call.
    public func start() {
        isStopped = false
        guard panels.isEmpty else { return }
        rebuildPanels()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isStopped else { return }
                    self.rebuildPanels()
                }
            }
        }
        if activityObserver == nil {
            activityObserver = NotificationCenter.default.addObserver(
                forName: .clickyModelActivityChanged, object: nil, queue: .main
            ) { [weak self] note in
                let activity = Self.companionActivity(from: note.object)
                Task { @MainActor in
                    guard let self, !self.isStopped else { return }
                    if let activity { self.setCompanionActivity(activity) }
                }
            }
        }
        if sessionObserver == nil {
            sessionObserver = NotificationCenter.default.addObserver(
                forName: Self.sessionStateNotification, object: nil, queue: .main
            ) { [weak self] note in
                let activity = Self.companionActivity(for: note.object as? SessionState)
                Task { @MainActor in
                    guard let self, !self.isStopped else { return }
                    if let activity { self.setCompanionActivity(activity) }
                }
            }
        }
    }

    public func stop() {
        isStopped = true
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let activityObserver {
            NotificationCenter.default.removeObserver(activityObserver)
            self.activityObserver = nil
        }
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
            self.sessionObserver = nil
        }
        dismissCard()
        cardPanel = nil
        cardHostingView = nil
        stopCompanionTracking()
        companionPolicy = CompanionTrackingPolicy()
        model.companion = .hidden
        model.companionPoints = [:]
        for record in panels { record.panel.orderOut(nil) }
        panels = []
        panelWindowIDs = []
        lastActiveScreenID = nil
        pendingConfirmation = nil
        model.presentations = [:]
    }

    /// Interface contract for the integration chunks: present each state at a
    /// global CG point/rect; `.hidden` clears every panel. Starts the overlay
    /// if `start()` was never called (no-op on the demo path). `.confirm` also
    /// shows the interactive card panel at the layout-computed position; every
    /// other state dismisses it.
    public func present(_ command: OverlayCommand) {
        start()
        if case .confirm = command {
            pendingConfirmation = command
        } else {
            pendingConfirmation = nil
        }
        apply(command, announcePrompt: true)
    }

    /// Resolves `command` against the current panels, publishes the per-screen
    /// presentations, and shows/dismisses the card panel accordingly. Also used
    /// by `rebuildPanels` to re-resolve a pending confirmation after a display
    /// change (without re-announcing it).
    private func apply(_ command: OverlayCommand, announcePrompt: Bool) {
        let presentations = OverlayPlacementResolver.resolve(command,
                                                             screens: panels.map(\.geometry),
                                                             lastActiveScreenID: lastActiveScreenID)
        model.presentations = Dictionary(presentations.map { ($0.screenID, $0) },
                                         uniquingKeysWith: { _, latest in latest })
        guard let first = presentations.first else {
            dismissCard()
            return
        }
        switch first.state {
        case .confirm:
            if announcePrompt { announce(first.accessibilityText, onScreen: first.screenID) }
            lastActiveScreenID = first.screenID
            if let prompt = first.accessibilityText,
               let geometry = panels.first(where: { $0.geometry.id == first.screenID })?.geometry {
                showCard(prompt: prompt, presentation: first, on: geometry)
            } else {
                dismissCard()
            }
        case .stopped:
            if announcePrompt { announce(first.accessibilityText, onScreen: first.screenID) }
            dismissCard()
        case .moving, .review:
            lastActiveScreenID = first.screenID
            dismissCard()
        }
    }

    /// Integration convenience API — the exact entry points the Chunk 13
    /// `OverlayAdapter` calls; all funnel into `present(_:)`.
    public func presentMoving(at point: CGPoint) { present(.moving(to: point)) }
    public func presentReview(rect: CGRect, label: String) { present(.review(rect: rect, label: label)) }
    public func presentConfirmation(rect: CGRect, label: String) {
        present(.confirm(rect: rect, point: CGPoint(x: rect.midX, y: rect.midY), prompt: label))
    }
    public func presentStopped(reason: String) { present(.stopped(reason: reason)) }

    /// Screen-parameter changes invalidate both the panel geometry and the
    /// resolved presentations, so the card panel is dismissed with them and the
    /// companion anchor is cleared (the next mouse tick republishes it). A
    /// pending confirmation is re-resolved against the new geometry afterwards
    /// so the card and its target box reappear correctly positioned; the gate
    /// itself lives in the safety layer and is never touched here.
    private func rebuildPanels() {
        dismissCard()
        for record in panels { record.panel.orderOut(nil) }
        model.presentations = [:]
        model.companionPoints = [:]
        let primaryHeight = Self.primaryHeight()
        self.primaryHeight = primaryHeight
        panels = NSScreen.screens.map { screen in
            let geometry = DisplayGeometry.from(screen: screen, primaryHeight: primaryHeight)
            let panel = OverlayPanel(screen: screen)
            let hosting = NSHostingView(rootView: GhostCursorView(model: model, screenID: geometry.id))
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hosting
            panel.orderFrontRegardless()
            return PanelRecord(geometry: geometry, panel: panel)
        }
        refreshPanelWindowIDs()
        if let pendingConfirmation {
            apply(pendingConfirmation, announcePrompt: false)
        }
    }

    // MARK: - Interactive confirmation card

    /// Shows the card panel centered exactly where the pure layout math
    /// (`OverlayLayout.cardCenter`) places the card for this presentation, on
    /// the screen that owns the confirm state. Called on every `.confirm` so a
    /// retarget/prompt change recomputes the frame.
    private func showCard(prompt: String, presentation: PanelPresentation, on screen: DisplayGeometry) {
        let panel = cardPanel ?? makeCardPanel(prompt: prompt)
        cardHostingView?.rootView = cardRootView(prompt: prompt)
        // The hosting view centers the card; sizing the panel to the measured
        // card + margin keeps long prompts unclipped while the card's center
        // stays at the panel center (the placement math below relies on that).
        let cardSize = cardHostingView?.fittingSize ?? OverlayLayout.cardSize
        let panelSize = OverlayLayout.cardPanelSize(fittingCard: cardSize)
        cardHostingView?.frame = CGRect(origin: .zero, size: panelSize)
        let localCenter = OverlayLayout.cardCenter(near: presentation.localRect, in: screen.cgFrame.size)
        let cgFrame = OverlayGeometry.globalFrame(centeredAtLocalPoint: localCenter,
                                                  size: panelSize,
                                                  onScreen: screen.cgFrame)
        panel.setFrame(OverlayGeometry.appKitFrame(fromCGGlobal: cgFrame, primaryHeight: primaryHeight),
                       display: true)
        panel.orderFrontRegardless()
        refreshPanelWindowIDs()
    }

    private func makeCardPanel(prompt: String) -> ConfirmationCardPanel {
        let panel = ConfirmationCardPanel(size: OverlayLayout.cardPanelSize)
        let hosting = CardHostingView(rootView: cardRootView(prompt: prompt))
        hosting.frame = CGRect(origin: .zero, size: OverlayLayout.cardPanelSize)
        panel.contentView = hosting
        cardHostingView = hosting
        cardPanel = panel
        return panel
    }

    /// Root view whose buttons forward to the live `onCardAction` hook, so the
    /// integration layer can rewire the gate at any time.
    private func cardRootView(prompt: String) -> ConfirmationCardView {
        ConfirmationCardView(prompt: prompt,
                             onConfirm: { [weak self] in self?.onCardAction?(.confirm) },
                             onCancel: { [weak self] in self?.onCardAction?(.cancel) })
    }

    /// Orders the card panel out (any non-confirm presentation, `stop()`). The
    /// panel is kept for reuse until `stop()` releases it, and stays listed in
    /// `panelWindowIDs` while it exists.
    private func dismissCard() {
        cardPanel?.orderOut(nil)
        refreshPanelWindowIDs()
    }

    /// Rebuilds the capture-exclusion list: every full-screen panel plus the
    /// card panel while its window exists (Task T-OVERLAY contract with the
    /// vision path).
    private func refreshPanelWindowIDs() {
        var ids = panels.map { CGWindowID($0.panel.windowNumber) }
        if let number = cardPanel?.windowNumber, number != 0 {
            ids.append(CGWindowID(number))
        }
        panelWindowIDs = ids
    }

    // MARK: - Ambient cursor companion

    /// Applies an activity from either notification contract and starts/stops
    /// the ~30 Hz mouse-follow timer — the loop stops completely while hidden
    /// (no idle wakeups).
    private func setCompanionActivity(_ activity: CompanionActivity) {
        let shouldTrack = companionPolicy.apply(activity)
        model.companion = activity
        if shouldTrack {
            startCompanionTracking()
        } else {
            stopCompanionTracking()
            model.companionPoints = [:]
        }
    }

    private func startCompanionTracking() {
        guard companionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishCompanionPoint() }
        }
        companionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCompanionTracking() {
        companionTimer?.invalidate()
        companionTimer = nil
    }

    /// One follow tick: read the AppKit mouse location, resolve the screen
    /// under it, and publish that screen's panel-local anchor. A pointer that
    /// is on no known display (reconfiguration gap) leaves the last anchor.
    private func publishCompanionPoint() {
        guard model.companion != .hidden else { return }
        guard let resolved = CompanionTracking.localPoint(appKitMouseLocation: NSEvent.mouseLocation,
                                                          primaryHeight: primaryHeight,
                                                          screens: panels.map(\.geometry)) else { return }
        model.companionPoints = [resolved.screenID: resolved.point]
    }

    /// Accepts both contract shapes for `.clickyModelActivityChanged`: a
    /// `CompanionActivity` or its `rawValue` string.
    nonisolated static func companionActivity(from object: Any?) -> CompanionActivity? {
        if let activity = object as? CompanionActivity { return activity }
        if let raw = object as? String { return CompanionActivity(rawValue: raw) }
        return nil
    }

    /// Fallback mapping from the session lifecycle when no explicit model
    /// activity has been posted: a live session at minimum shows the listening
    /// buddy; idle/stopped hide it. `.reconnecting` leaves the current state
    /// alone — the model-activity contract owns that transition.
    nonisolated static func companionActivity(for state: SessionState?) -> CompanionActivity? {
        switch state {
        case .listening: return .listening
        case .idle, .stopped: return .hidden
        case .reconnecting, .none: return nil
        }
    }

    /// VoiceOver announcement so the prompt reaches users even though the panel
    /// never becomes key (spec §4.3: the card is VoiceOver-readable).
    private func announce(_ text: String?, onScreen screenID: UInt32) {
        guard let text,
              let element = panels.first(where: { $0.geometry.id == screenID })?.panel.contentView else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// AppKit → CG flip anchor: the primary screen (origin {0,0}) supplies the
    /// height for `CoordinateMath.cgFrame(fromAppKit:primaryHeight:)`.
    private static func primaryHeight() -> CGFloat {
        (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }
}

extension DisplayGeometry {
    /// Bridges an `NSScreen` into the coordinate model shared with AX, CGEvent
    /// and ScreenCaptureKit. `NSScreenNumber` is the `CGDirectDisplayID`.
    static func from(screen: NSScreen, primaryHeight: CGFloat) -> DisplayGeometry {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return DisplayGeometry(id: number?.uint32Value ?? 0,
                               cgFrame: CoordinateMath.cgFrame(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                               appKitFrame: screen.frame,
                               scaleFactor: screen.backingScaleFactor)
    }
}
