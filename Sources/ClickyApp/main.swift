import AppKit
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // dev parity; the .app sets LSUIElement instead
    app.run()
}
