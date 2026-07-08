import AppKit
import ServiceManagement
import SwiftUI
import CosmodromeCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcutDisplay: String
    @Published var launchAtLogin: Bool
    @Published var statusMessage: String?

    let state: GridState
    private let hotkey: HotkeyManager
    var onShortcutChanged: () -> Void = {}

    init(state: GridState, hotkey: HotkeyManager) {
        self.state = state
        self.hotkey = hotkey
        self.shortcutDisplay = hotkey.displayString
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setShortcut(keyCode: UInt32, carbonModifiers: UInt32) {
        hotkey.update(keyCode: keyCode, modifiers: carbonModifiers)
        shortcutDisplay = hotkey.displayString
        onShortcutChanged()
    }

    /// While the recorder is armed, the current combo must be capturable —
    /// suspend the Carbon registration so it arrives as a plain keyDown.
    func setRecording(_ active: Bool) {
        hotkey.setSuspended(active)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            statusMessage = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            statusMessage = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?

    func show(model: SettingsModel) {
        self.model = model
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 0),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Cosmodrome Settings"
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: SettingsView(model: model))
            win.center()
            window = win
        } else {
            window?.contentView = NSHostingView(rootView: SettingsView(model: model))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var state: GridState

    init(model: SettingsModel) {
        self.model = model
        self.state = model.state
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Open app grid") {
                    ShortcutRecorderView(
                        current: model.shortcutDisplay,
                        onRecordingChanged: { model.setRecording($0) }
                    ) { keyCode, mods in
                        model.setShortcut(keyCode: keyCode, carbonModifiers: mods)
                    }
                }
            }
            Section("Appearance") {
                LabeledContent("Background dimming") {
                    Slider(value: $state.dimAmount, in: 0...0.6)
                        .frame(width: 180)
                }
            }
            Section("General") {
                Toggle("Start Cosmodrome at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// Click, press the new combo, done. Esc cancels.
struct ShortcutRecorderView: View {
    let current: String
    var onRecordingChanged: (Bool) -> Void = { _ in }
    let onRecord: (UInt32, UInt32) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : current) {
            recording ? stopRecording() : startRecording()
        }
        .onDisappear { stopRecording() }
        // The Settings window is retained across closes (isReleasedWhenClosed
        // = false), so onDisappear never fires for the close button; without
        // this, an armed monitor would survive invisibly and swallow — or
        // silently rebind the hotkey to — the next key typed anywhere in the app.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            stopRecording()
        }
    }

    private func startRecording() {
        recording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            if event.keyCode == 53 { return nil } // Esc cancels

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbon: UInt32 = 0
            if flags.contains(.command) { carbon |= CarbonModifiers.command }
            if flags.contains(.shift) { carbon |= CarbonModifiers.shift }
            if flags.contains(.option) { carbon |= CarbonModifiers.option }
            if flags.contains(.control) { carbon |= CarbonModifiers.control }

            let isFunctionKey = (96...122).contains(Int(event.keyCode))
            guard carbon != 0 || isFunctionKey else {
                NSSound.beep() // bare letter keys would swallow all typing, system-wide
                return nil
            }
            onRecord(UInt32(event.keyCode), carbon)
            return nil
        }
    }

    private func stopRecording() {
        guard recording || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecordingChanged(false)
    }
}
