import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = GridState()
    private(set) lazy var overlay = OverlayController(state: state)
    let hotkey = HotkeyManager()
    private var statusItem: StatusItemController?
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        hotkey.onHotkey = { [weak self] in self?.overlay.toggle() }
        hotkey.loadAndRegister()

        statusItem = StatusItemController(
            hotkey: hotkey,
            onOpen: { [weak self] in self?.overlay.show() },
            onRefresh: { [weak self] in self?.state.refreshApps() },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) },
            onArrangeAlphabetical: { [weak self] in self?.state.arrangeAlphabetically() },
            onArrangeByCategory: { [weak self] in self?.state.arrangeByCategory() }
        )

        // Demo/testing modes mutate the layout; keep them off the user's disk.
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--ephemeral") {
            state.persistenceEnabled = false
        }
        state.bootstrap()
        if let screen = NSScreen.main {
            WallpaperProvider.prepare(for: screen)
        }
        handleLaunchArguments()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the app in Finder or a Dock alias = "open the grid",
        // exactly like the old Launchpad tile.
        overlay.show()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        overlay.hideBecauseDeactivated()
    }

    private func showSettings() {
        if overlay.isVisible { overlay.hide(restoreFocus: false) }
        settings.show(model: makeSettingsModel())
    }

    private func makeSettingsModel() -> SettingsModel {
        let model = SettingsModel(state: state, hotkey: hotkey)
        model.onShortcutChanged = { [weak self] in
            self?.statusItem?.refreshShortcutDisplay()
        }
        return model
    }

    // MARK: - Launch behavior

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("--arranged") {
            state.arrangeByCategory()
        }
        let background = args.contains("--background") || Self.launchedAsLoginItem()
        if !background {
            overlay.show()
        }
        if let queryIndex = args.firstIndex(of: "--query"), args.indices.contains(queryIndex + 1) {
            state.setQuery(args[queryIndex + 1])
        }
        if let pageIndex = args.firstIndex(of: "--page"), args.indices.contains(pageIndex + 1),
           let page = Int(args[pageIndex + 1]) {
            state.goToPage(page)
        }
        if args.contains("--demo") {
            runDemo()
        }
    }

    /// Detects the login-item launch so the grid doesn't pop over the desktop
    /// at every boot. (kAEOpenApplication + keyAELaunchedAsLogInItem.)
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let keyAEPropDataCode = AEKeyword(0x7072_6474)          // 'prdt'
        let launchedAsLogInItemCode: UInt32 = 0x6C67_6974       // 'lgit'
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropDataCode)?.enumCodeValue == launchedAsLogInItemCode
    }

    /// Self-driving tour — real state changes, no synthetic input events.
    /// (The README gif is recorded with genuine system input instead.)
    private func runDemo() {
        Task { @MainActor [state, overlay] in
            func pause(_ seconds: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            await pause(1.4)
            state.arrangeByCategory()
            await pause(1.6)
            if let folder = state.layout.nodes.compactMap(\.folder).first {
                state.openFolder(folder.id)
                await pause(1.8)
                state.closeFolder()
                await pause(0.8)
            }
            state.flipPage(1)
            await pause(1.2)
            state.goToPage(0)
            await pause(0.9)
            for ch in "ca" {
                state.appendToQuery(String(ch))
                await pause(0.35)
            }
            await pause(1.6)
            state.setQuery("")
            await pause(1.0)
            overlay.hide(restoreFocus: false)
        }
    }
}
