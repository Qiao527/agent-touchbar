import AppKit

// The entry point runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    // Menu bar icon only; no Dock icon.
    app.setActivationPolicy(.accessory)
    app.run()
}
