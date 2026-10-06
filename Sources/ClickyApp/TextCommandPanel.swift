import AppKit

/// The text-command fallback for users who cannot speak clearly (spec §2:
/// voice-first, not voice-only). The panel explicitly activates Clicky and takes
/// key focus while open — required for typing to land reliably in an LSUIElement
/// app running in the background — and Esc or Close dismisses it. Submitted text
/// goes to `SessionCoordinator.submitTypedCommand`, which routes it through the
/// same local channels as speech (intent ledger + confirmation gate) before
/// sending it to the Live model as a text turn.
@MainActor
final class TextCommandPanelController {
    static let shared = TextCommandPanelController()

    private var panel: TextCommandPanel?

    private init() {}

    /// Shows (or re-focuses) the panel. `onSubmit` runs on the main actor with
    /// the trimmed, non-empty command text; the panel closes itself afterwards.
    func show(onSubmit: @escaping @MainActor (String) -> Void) {
        let panel = panel ?? TextCommandPanel()
        self.panel = panel
        panel.onSubmit = onSubmit
        panel.prepareForPresentation()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.focusCommandField()
    }
}

/// Small floating panel: one text field, Send (Return), Close (Esc). Kept alive
/// across shows (`isReleasedWhenClosed = false`) so re-opening is instant.
@MainActor
private final class TextCommandPanel: NSPanel {
    var onSubmit: (@MainActor (String) -> Void)?

    private let commandField = NSTextField()
    private let caption = NSTextField(labelWithString:
        "Voice-first, not voice-only — typed commands and confirmations (\"haan\", \"confirm\") work like speech.")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 88),
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        title = "Type a Command"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        buildContent()
    }

    override var canBecomeKey: Bool { true }

    /// Esc while the field editor is first responder forwards here.
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    func prepareForPresentation() {
        commandField.stringValue = ""
        centerOnMouseScreen()
    }

    func focusCommandField() {
        makeFirstResponder(commandField)
        commandField.currentEditor()?.selectAll(nil)
    }

    private func buildContent() {
        let content = NSView()
        contentView = content

        commandField.placeholderString = "Type a command — e.g. \"open Safari\", or \"haan\" to confirm"
        commandField.font = .systemFont(ofSize: 15)
        commandField.target = self
        commandField.action = #selector(submit)
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.setAccessibilityLabel("Command")

        let send = NSButton(title: "Send", target: self, action: #selector(submit))
        send.bezelStyle = .rounded
        send.keyEquivalent = "\r"
        send.translatesAutoresizingMaskIntoConstraints = false
        send.setAccessibilityLabel("Send command")

        let close = NSButton(title: "Close", target: self, action: #selector(closePanel))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setAccessibilityLabel("Close without sending")

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        for view in [commandField, send, close, caption] as [NSView] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            commandField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            commandField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            send.leadingAnchor.constraint(equalTo: commandField.trailingAnchor, constant: 8),
            send.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            close.leadingAnchor.constraint(equalTo: send.trailingAnchor, constant: 8),
            close.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            caption.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            caption.topAnchor.constraint(equalTo: commandField.bottomAnchor, constant: 8),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])
    }

    @objc private func submit() {
        let text = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        // Clear before dispatching: Return can reach both the field action and
        // the default button, and the empty-field guard makes a double fire inert.
        commandField.stringValue = ""
        onSubmit?(text)
        orderOut(nil)
    }

    @objc private func closePanel() { orderOut(nil) }

    /// Centers horizontally on the screen under the pointer (multi-display safe),
    /// near its top edge, like a command palette.
    private func centerOnMouseScreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let size = frame.size
        setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                               y: screen.frame.maxY - size.height - 140))
    }
}
