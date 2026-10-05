import AppKit
import ApplicationServices
import AVFoundation
import ClickyCore
/// Live TCC checks + polling watchdog + per-app Automation pre-trigger.
@MainActor
final class PermissionsCenter {
    static let shared = PermissionsCenter()
    private(set) var snapshot = PermissionSnapshot()
    var onRevocation: ((PermissionKind) -> Void)?
    private var watchdogTimer: Timer?
    private init() {}
    func refresh() -> PermissionSnapshot {
        snapshot = PermissionSnapshot(accessibility: AXIsProcessTrusted() ? .granted : .denied,
                                      screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied,
                                      microphone: Self.microphoneStatus())
        return snapshot
    }
    func startWatchdog(every seconds: TimeInterval = 2.0) {
        stopWatchdog()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func stopWatchdog() { watchdogTimer?.invalidate(); watchdogTimer = nil }
    private func tick() {
        let before = snapshot
        let after = refresh()
        for kind in PermissionWatchdog.revocations(from: before, to: after) { onRevocation?(kind) }
    }
    private static func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .denied   // policy-blocked (parental controls/MDM), not grantable
        @unknown default: return .unknown
        }
    }
    func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in completion(granted) }
        }
    }
    /// Ask macOS whether automating `bundleID` needs consent, prompting now if
    /// so. Returns noErr / errAEEventWouldRequireUserConsent / errAEEventNotPermitted.
    @discardableResult
    static func preflightAutomation(bundleID: String) -> OSStatus {
        var target = AEDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBufferPointer { buffer in
            AECreateDesc(DescType(typeApplicationBundleID), buffer.baseAddress, buffer.count, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard),
                                                     AEEventID(typeWildCard), true)
    }
}
