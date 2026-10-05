import AppKit
import ClickyCore
/// Sequential first-run wizard (one NSAlert per permission, exact deep links,
/// re-check without relaunch; Screen Recording notes the restart requirement).
@MainActor
final class PermissionsWindowController {
    static let shared = PermissionsWindowController()
    private init() {}
    func show() { runStep(index: 0) }
    private func runStep(index: Int) {
        let kinds = PermissionKind.allCases
        guard index < kinds.count else { runAutomationPreflight(); return }
        let kind = kinds[index]
        let status = PermissionsCenter.shared.refresh().status(for: kind)
        let alert = NSAlert()
        alert.messageText = "Permission \(index + 1) of \(kinds.count): \(kind.displayName)"
        alert.informativeText = "\(kind.guidance)\n\nCurrent status: \(status)"
        alert.addButton(withTitle: status.isGranted ? "Next" : "Open System Settings")
        alert.addButton(withTitle: "Re-check")
        alert.addButton(withTitle: status.isGranted ? "Next" : "Skip for now")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if status.isGranted { runStep(index: index + 1) }
            else { NSWorkspace.shared.open(kind.settingsURL); runStep(index: index) }
        case .alertSecondButtonReturn:
            if kind == .microphone { PermissionsCenter.shared.requestMicrophone { _ in } }
            runStep(index: index)
        default:
            runStep(index: index + 1)
        }
    }
    private func runAutomationPreflight() {
        let targets = ["com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.apple.systemevents"]
        let results = targets.map { ($0, PermissionsCenter.preflightAutomation(bundleID: $0)) }
        let alert = NSAlert()
        alert.messageText = "Automation pre-flight complete"
        alert.informativeText = results.map { "\($0.0): OSStatus \($0.1)" }.joined(separator: "\n")
            + "\n\nConsent dialogs were handled now so they never interrupt a demo."
        alert.runModal()
    }
}
