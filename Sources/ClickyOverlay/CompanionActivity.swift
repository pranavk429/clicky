import CoreGraphics
import ClickyCore
import Foundation

/// Ambient cursor companion states (Task T-OVERLAY). The companion gives the
/// user a visible presence while the app is otherwise invisible — it follows
/// the pointer during a session and disappears when idle.
///
/// The model layer owns the activity signal; `ClickyOverlay` never infers it.
/// The session layer posts `.clickyModelActivityChanged` with the activity (or
/// its `rawValue` string) as the notification `object`.
public enum CompanionActivity: String, Sendable, CaseIterable {
    case hidden
    case listening
    case thinking
    case speaking
}

extension Notification.Name {
    /// Contract with the session/model layer: post with `object` set to a
    /// `CompanionActivity` or its `rawValue` string (both are accepted) to
    /// drive the ambient cursor companion.
    public static let clickyModelActivityChanged = Notification.Name("clickyModelActivityChanged")
}

/// Pure timer-lifecycle policy for the companion's mouse-follow loop: the
/// controller applies each activity and runs the ~30 Hz timer only while the
/// result is `true` — the loop stops completely while hidden (power). Extracted
/// so the lifecycle is unit-tested without a window server.
struct CompanionTrackingPolicy: Equatable {
    private(set) var activity: CompanionActivity = .hidden

    var isTracking: Bool { activity != .hidden }

    /// Applies `newActivity`; returns `true` when the follow timer must run.
    @discardableResult
    mutating func apply(_ newActivity: CompanionActivity) -> Bool {
        activity = newActivity
        return isTracking
    }
}

/// Pure mouse → panel resolution for the companion. `NSEvent.mouseLocation`
/// arrives in AppKit global coordinates (bottom-left of the primary, y up);
/// the companion renders in panel-local top-left coordinates.
enum CompanionTracking {
    /// Resolves the AppKit mouse location to the screen under the pointer and
    /// that screen's panel-local point. `nil` when the pointer is not on any
    /// known display (e.g. a display gap during reconfiguration).
    static func localPoint(appKitMouseLocation: CGPoint,
                           primaryHeight: CGFloat,
                           screens: [DisplayGeometry]) -> (screenID: UInt32, point: CGPoint)? {
        let cgPoint = CoordinateMath.cgPoint(fromAppKit: appKitMouseLocation, primaryHeight: primaryHeight)
        guard let screen = CoordinateMath.display(containing: cgPoint, in: screens) else { return nil }
        return (screen.id, OverlayGeometry.localPoint(fromCGGlobal: cgPoint, onScreen: screen.cgFrame))
    }
}
