import AppKit
import ClickyCore
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notice: String?
    private let state = AppState.shared
    private var demoRunner: ScriptedDemoRunner?
    private var liveRunner: LiveConversationRunner?
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
        if CommandLine.arguments.contains("--scripted-demo") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.runScriptedDemo()
            }
        }
        if CommandLine.arguments.contains("--live-demo") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.runLiveDemo()
            }
        }
    }
    @objc private func toggleSession() { state.toggleSession() }
    @objc private func showPermissions() { PermissionsWindowController.shared.show() }
    @objc private func runScriptedDemo() {
        let runner = demoRunner ?? ScriptedDemoRunner()
        demoRunner = runner
        runner.start()
    }
    @objc private func stopScriptedDemo() {
        if let runner = demoRunner {
            Task { await runner.stop(reason: .userToggle) }
        }
    }
    @objc private func runLiveDemo() {
        let runner = liveRunner ?? LiveConversationRunner()
        liveRunner = runner
        Task { await runner.start() }
    }
    @objc private func stopLiveDemo() {
        if let runner = liveRunner {
            Task { await runner.stop(reason: .userToggle) }
        }
    }
    @objc private func toggleHalfDuplex() {
        let runner = liveRunner ?? LiveConversationRunner()
        liveRunner = runner
        runner.halfDuplex.toggle()
        rebuildMenu()
    }
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
        let runDemo = NSMenuItem(title: "Run Scripted Demo", action: #selector(runScriptedDemo), keyEquivalent: "")
        runDemo.target = self
        menu.addItem(runDemo)
        let stopDemo = NSMenuItem(title: "Stop Demo (Esc)", action: #selector(stopScriptedDemo), keyEquivalent: "")
        stopDemo.target = self
        menu.addItem(stopDemo)
        let runLive = NSMenuItem(title: "Start Live Conversation (English)", action: #selector(runLiveDemo), keyEquivalent: "")
        runLive.target = self
        menu.addItem(runLive)
        let stopLive = NSMenuItem(title: "Stop Live Demo (Esc)", action: #selector(stopLiveDemo), keyEquivalent: "")
        stopLive.target = self
        menu.addItem(stopLive)
        let halfDuplex = NSMenuItem(title: "Half-duplex (mute mic while speaking): \(liveRunner?.halfDuplex == true ? "On" : "Off")",
                                    action: #selector(toggleHalfDuplex), keyEquivalent: "")
        halfDuplex.target = self
        menu.addItem(halfDuplex)
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
