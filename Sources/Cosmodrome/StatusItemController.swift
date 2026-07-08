import AppKit

/// The little grid in the menu bar: open, refresh, settings, quit.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let hotkey: HotkeyManager
    private let onOpen: () -> Void
    private let onRefresh: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var openMenuItem: NSMenuItem?

    init(
        hotkey: HotkeyManager,
        onOpen: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.hotkey = hotkey
        self.onOpen = onOpen
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: "Cosmodrome"
            )
        }
        statusItem.menu = buildMenu()
        refreshShortcutDisplay()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open App Grid", action: #selector(openGrid), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openMenuItem = open

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Apps", action: #selector(refreshApps), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Cosmodrome", action: #selector(openGitHub), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Cosmodrome", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Shows the current global shortcut next to "Open App Grid".
    func refreshShortcutDisplay() {
        guard let item = openMenuItem else { return }
        item.title = "Open App Grid    \(hotkey.displayString)"
    }

    @objc private func openGrid() { onOpen() }
    @objc private func refreshApps() { onRefresh() }
    @objc private func openSettings() { onSettings() }
    @objc private func quit() { onQuit() }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/cleoanka/cosmodrome") {
            NSWorkspace.shared.open(url)
        }
    }
}
