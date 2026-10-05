import AppKit
import ClickyCore
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notice: String?
    private let state = AppState.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Clicky — voice cursor"
        statusItem = item
        rebuildMenu()
        NotificationCenter.default.addObserver(forName: .clickySessionStateChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenu() }
        }
        PermissionsCenter.shared.startWatchdog()
        PermissionsCenter.shared.onRevocation = { [weak self] kind in
            Task { @MainActor in self?.setNotice("\(kind.displayName) permission was revoked — open Permissions & First-Run Setup.") }
        }
    }
    @objc private func toggleSession() { state.toggleSession() }
    @objc private func showPermissions() { PermissionsWindowController.shared.show() }
    func setNotice(_ text: String?) { notice = text; rebuildMenu() }
    private func rebuildMenu() {
        guard let item = statusItem else { return }
        item.button?.image = Self.icon(for: state.session)
        let menu = NSMenu()
        if let notice {
            let noticeItem = NSMenuItem(title: "⚠️ \(notice)", action: nil, keyEquivalent: "")
            noticeItem.isEnabled = false
            menu.addItem(noticeItem)
        }
        let status = NSMenuItem(title: Self.statusText(for: state.session), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: state.session.isActive ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleSession), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let permissions = NSMenuItem(title: "Permissions & First-Run Setup…", action: #selector(showPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clicky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }
    private static func statusText(for state: SessionState) -> String {
        switch state {
        case .idle: return "Idle — mic off"
        case .listening: return "● Listening"
        case .reconnecting(let r): return "Reconnecting… (\(r))"
        case .stopped(let r): return "Stopped (\(r.rawValue))"
        }
    }
    private static func icon(for state: SessionState) -> NSImage? {
        switch state {
        case .idle, .stopped: return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Clicky idle")
        case .listening: return NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Clicky listening")
        case .reconnecting: return NSImage(systemSymbolName: "wifi.exclamationmark", accessibilityDescription: "Clicky reconnecting")
        }
    }
}
