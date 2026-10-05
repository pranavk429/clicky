import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Wave 2b demo gate: a real, user-confirmed mouse click whose only target is
/// Clicky's own on-screen panel. The gate never reports success unless the
/// synthesised click actually fired the panel's button (`didFire`); a missed
/// click is reported as unconfirmed, so the overlay can never claim a click
/// that did not happen.
@MainActor
final class DemoClickGate: NSObject {
    private let window: NSWindow
    private let button: NSButton
    private var monitor: Any?
    private var pending: CheckedContinuation<Bool, Never>?
    private var buttonDidFire = false
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.title = "Clicky live-slice test target — this click is real"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        let button = NSButton(title: "Demo target", target: nil, action: #selector(DemoClickGate.buttonFired))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 80, y: 40, width: 200, height: 32)
        button.keyEquivalent = ""
        self.button = button

        super.init()

        button.target = self
        window.contentView?.addSubview(button)
    }

    /// Brings the panel forward without activating the app — visible, non-key.
    func showPanel() {
        window.orderFrontRegardless()
    }

    /// Hides the panel; safe to call when it is already hidden.
    func hidePanel() {
        window.orderOut(nil)
    }

    /// Activates the app and makes the panel key so the confirmation keys land here.
    func beginGate() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The demo button's centre in AppKit screen coordinates (bottom-left origin).
    func buttonScreenCenter() -> CGPoint {
        let inWindowRect = button.convert(button.bounds, to: nil)
        let inWindow = NSPoint(x: inWindowRect.midX, y: inWindowRect.midY)
        return window.convertPoint(toScreen: inWindow)
    }

    /// Waits for Return (confirm) or Esc (cancel, never swallowed) in the demo panel.
    /// Resolves exactly once; a timeout resolves `false`.
    func requestConfirmation(timeoutSeconds: Double = 20) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pending = continuation
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch Int(event.keyCode) {
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    self.resolve(true)
                    return nil
                case kVK_Escape:
                    // Never swallow Esc — the Carbon hard stop must still fire.
                    self.resolve(false)
                    return event
                default:
                    return event
                }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                self?.resolve(false)
            }
        }
    }

    /// Posts a real left click at `point`; the caller waits, then reads `didFire`.
    @discardableResult
    func performRealClick(at point: CGPoint) -> Bool {
        buttonDidFire = false
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseDown,
                                 mouseCursorPosition: point,
                                 mouseButton: .left),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseUp,
                               mouseCursorPosition: point,
                               mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Whether the last synthesised click actually hit the demo button.
    var didFire: Bool { buttonDidFire }

    /// Session stop / safety: resolve any waiting gate as not confirmed.
    func cancelPending() {
        resolve(false)
    }

    @objc private func buttonFired() {
        buttonDidFire = true
    }

    /// Resumes the waiting continuation at most once and tears the monitor down.
    private func resolve(_ value: Bool) {
        guard let continuation = pending else { return }
        pending = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: value)
    }
}
