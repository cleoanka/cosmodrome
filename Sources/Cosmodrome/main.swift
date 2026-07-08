import AppKit

// Top-level code runs on the main thread; tell the compiler so.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
