import Foundation
/// The three TCC permissions Clicky needs, with exact System Settings deep
/// links and honest remediation (spec §4.6). Automation is per target app and
/// is handled by `PermissionsCenter.preflightAutomation`.
public enum PermissionKind: String, CaseIterable, Sendable {
    case accessibility, screenRecording, microphone
    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .microphone: return "Microphone"
        }
    }
    public var settingsURL: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .microphone: "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
    }
    public var guidance: String {
        switch self {
        case .accessibility:
            return "Lets Clicky inspect UI elements and post clicks/keystrokes. Grant it, then Clicky re-checks automatically."
        case .screenRecording:
            return "Only used by the on-demand vision fallback. After granting, you MUST quit and reopen Clicky (macOS restart requirement)."
        case .microphone:
            return "Lets a voice session hear you. The mic runs only while a session is active."
        }
    }
}
public enum PermissionStatus: Equatable, Sendable {
    case granted, denied, notDetermined, unknown
    public var isGranted: Bool { self == .granted }
}
public struct PermissionSnapshot: Equatable, Sendable {
    public var accessibility: PermissionStatus
    public var screenRecording: PermissionStatus
    public var microphone: PermissionStatus
    public init(accessibility: PermissionStatus = .unknown, screenRecording: PermissionStatus = .unknown,
                microphone: PermissionStatus = .unknown) {
        self.accessibility = accessibility; self.screenRecording = screenRecording; self.microphone = microphone
    }
    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind { case .accessibility: return accessibility; case .screenRecording: return screenRecording; case .microphone: return microphone }
    }
    public var allGranted: Bool { accessibility.isGranted && screenRecording.isGranted && microphone.isGranted }
    public var missing: [PermissionKind] { PermissionKind.allCases.filter { !status(for: $0).isGranted } }
}
public enum PermissionWatchdog {
    /// Kinds granted in `old` but no longer granted in `new`.
    public static func revocations(from old: PermissionSnapshot, to new: PermissionSnapshot) -> [PermissionKind] {
        PermissionKind.allCases.filter { old.status(for: $0).isGranted && !new.status(for: $0).isGranted }
    }
}
