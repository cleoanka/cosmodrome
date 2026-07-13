import AppKit
import SwiftUI
import CosmodromeCore

/// A Spotlight-style panel: takes the keyboard without activating the app,
/// so the overlay pops instantly over whatever the user was doing and gives
/// focus straight back when it closes.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the full-screen overlay window, all keyboard/scroll routing while it
/// is up, and the show / launch / hide transitions.
@MainActor
final class OverlayController: NSObject {
    private let state: GridState
    private var window: OverlayPanel?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?
    private(set) var isVisible = false
    private var isTransitioning = false

    // Trackpad swipe inside an open folder: one page per gesture.
    private var folderSwipeAccumulator: CGFloat = 0
    private var folderSwipeConsumed = false
    // Classic mouse wheels have no gesture phases; rate-limit instead.
    private var wheelAccumulator: CGFloat = 0
    private var wheelCooldownUntil: CFAbsoluteTime = 0

    init(state: GridState) {
        self.state = state
        super.init()
        state.onHideRequest = { [weak self] in self?.hide() }
        state.onLaunchRequest = { [weak self] item in self?.launch(item) }
        state.onRevealRequest = { [weak self] item in self?.reveal(item) }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - Show

    func show() {
        guard !isVisible, !isTransitioning else { return }
        guard let screen = Self.screenWithMouse() else { return }

        // Instant cache lookup; on a cold miss the opaque gradient covers the
        // few hundred ms until the async blur lands.
        state.wallpaper = WallpaperProvider.cached(for: screen)
        if state.wallpaper == nil {
            WallpaperProvider.prepare(for: screen) { [weak self] image in
                guard let self, self.isVisible, let image else { return }
                withAnimation(.easeInOut(duration: 0.35)) { self.state.wallpaper = image }
            }
        }
        state.resetForShow()

        let win = ensureWindow()
        win.setFrame(screen.frame, display: true)
        win.makeKeyAndOrderFront(nil)

        isVisible = true
        installMonitors()
        state.refreshApps()

        // Let the hidden state land on screen first, then animate in.
        DispatchQueue.main.async { [state] in
            withAnimation(Anim.appear) { state.phase = .shown }
        }
    }

    // MARK: - Hide

    func hide(restoreFocus: Bool = true) {
        guard isVisible, !isTransitioning else { return }
        isTransitioning = true
        state.drag.cancel()
        removeMonitors()
        withAnimation(Anim.disappear) { state.phase = .hidden }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.finishHide(restoreFocus: restoreFocus)
        }
    }

    /// The user clicked into another app: drop the overlay instantly,
    /// no animation — they have already moved on.
    func hideBecauseDeactivated() {
        guard isVisible, !isTransitioning else { return }
        state.drag.cancel()
        removeMonitors()
        state.phase = .hidden
        window?.orderOut(nil)
        isVisible = false
    }

    private func finishHide(restoreFocus: Bool) {
        window?.orderOut(nil)
        isVisible = false
        isTransitioning = false
    }

    // MARK: - Launch & reveal

    /// "Show in Finder": the overlay must get out of the way, or the revealed
    /// window sits invisible behind a full-screen panel.
    func reveal(_ item: AppItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        hide(restoreFocus: false)
    }

    func launch(_ item: AppItem) {
        guard isVisible, !isTransitioning else { return }
        isTransitioning = true
        removeMonitors()
        NSWorkspace.shared.openApplication(at: item.url, configuration: NSWorkspace.OpenConfiguration())
        withAnimation(Anim.launch) { state.phase = .launching }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            self?.finishHide(restoreFocus: false)
        }
    }

    // MARK: - Window

    private func ensureWindow() -> OverlayPanel {
        if let window { return window }
        let win = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        // One above the menu bar: covers everything, exactly like Launchpad did.
        win.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.animationBehavior = .none
        win.contentView = NSHostingView(rootView: OverlayRootView(state: state))
        window = win
        return win
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - Event monitors

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, !self.isTransitioning else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isVisible, !self.isTransitioning else { return event }
            self.handleScroll(event)
            return nil
        }
        // Clicks that land in other apps never reach us as local events;
        // a global mouse monitor (no permissions needed) closes the overlay.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hideBecauseDeactivated() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        scrollMonitor = nil
        outsideClickMonitor = nil
    }

    /// Returns true when the event was consumed. Everything is consumed while
    /// the overlay is up — unhandled keys in a borderless window would beep.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // A drag in flight: Escape cancels it, everything else is inert.
        if state.drag.isActive {
            if event.keyCode == 53 { state.drag.cancel() }
            return true
        }

        // Folder rename captures the keyboard (headless — no focusable field).
        if state.renamingFolder {
            switch event.keyCode {
            case 53: state.cancelRename(); return true
            case 36, 76, 48: state.commitRename(); return true
            case 51: state.renameBackspace(); return true
            default: break
            }
            if flags.contains(.command) || flags.contains(.control) { return true }
            if let text = printableText(from: event) { state.renameAppend(text) }
            return true
        }

        // An open folder gets its own navigation layer.
        if state.openFolderID != nil {
            switch event.keyCode {
            case 53: state.closeFolder(); return true
            case 36, 76:
                if let item = state.selectedFolderApp { launch(item) }
                return true
            case 123: state.moveFolderSelection(.left); return true
            case 124: state.moveFolderSelection(.right); return true
            case 125: state.moveFolderSelection(.down); return true
            case 126: state.moveFolderSelection(.up); return true
            case 48:
                state.moveFolderSelection(flags.contains(.shift) ? .left : .right)
                return true
            case 116: state.folderFlip(-1); return true
            case 121: state.folderFlip(1); return true
            case 51: return true
            default: break
            }
            if flags.contains(.command) || flags.contains(.control) { return true }
            if let text = printableText(from: event) {
                // Typing anywhere searches globally, so the folder gives way.
                state.closeFolder()
                state.appendToQuery(text)
            }
            return true
        }

        switch event.keyCode {
        case 53: // Escape: clear the search first, then dismiss.
            if state.query.isEmpty { hide() } else { state.setQuery("") }
            return true
        case 36, 76: // Return / keypad Enter
            if !state.query.isEmpty {
                if let item = state.searchItemToLaunch() { launch(item) }
                return true
            }
            switch state.selectedNode {
            case .app(let appID):
                if let item = state.appsByID[appID] { launch(item) }
            case .folder(let folder):
                state.openFolder(folder.id)
            case nil:
                break
            }
            return true
        case 123: state.moveSelection(.left); return true
        case 124: state.moveSelection(.right); return true
        case 125: state.moveSelection(.down); return true
        case 126: state.moveSelection(.up); return true
        case 48: // Tab
            state.moveSelection(flags.contains(.shift) ? .left : .right)
            return true
        case 116: state.flipPage(-1); return true // Page Up
        case 121: state.flipPage(1); return true  // Page Down
        case 115: state.goToPage(0); return true                    // Home
        case 119: state.goToPage(state.pageCount - 1); return true  // End
        case 51: // Delete
            state.backspace()
            return true
        default:
            break
        }

        if flags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "v",
               let pasted = NSPasteboard.general.string(forType: .string) {
                state.appendToQuery(pasted.replacingOccurrences(of: "\n", with: " "))
            } else if event.charactersIgnoringModifiers?.lowercased() == "q" {
                // Muscle-memory ⌘Q closes the overlay, never the whole app.
                hide()
            }
            return true
        }
        if flags.contains(.control) { return true }

        if let text = printableText(from: event) {
            state.appendToQuery(text)
        }
        return true
    }

    private func printableText(from event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else { return nil }
        let printable = String(chars.unicodeScalars.filter { scalar in
            !(0xF700...0xF8FF).contains(Int(scalar.value))
                && !CharacterSet.controlCharacters.contains(scalar)
        })
        return printable.isEmpty ? nil : printable
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta = abs(dx) >= abs(dy) ? dx : dy

        // An open folder pages discretely.
        if state.openFolderID != nil {
            handleFolderScroll(event, delta: delta)
            return
        }

        if event.phase.isEmpty {
            // Classic wheel ticks.
            wheelAccumulator += delta
            let now = CFAbsoluteTimeGetCurrent()
            if now >= wheelCooldownUntil, abs(wheelAccumulator) > 30 {
                // Natural scrolling: content follows the fingers.
                state.flipPage(wheelAccumulator > 0 ? -1 : 1)
                wheelAccumulator = 0
                wheelCooldownUntil = now + 0.3
            }
            return
        }

        // Trackpad gesture: the pager tracks the fingers 1:1 and snaps with
        // a flick-aware spring on release — the v0.2 interactive feel.
        let drive = state.pagerDrive
        switch event.phase {
        case .began:
            drive.gestureActive = true
            drive.liveOffset = 0
            drive.lastDelta = 0
            fallthrough
        case .changed:
            drive.liveOffset += delta
            drive.lastDelta = delta
        case .ended, .cancelled:
            if drive.gestureActive { state.settlePager() }
        default:
            break
        }
    }

    private func handleFolderScroll(_ event: NSEvent, delta: CGFloat) {
        if event.phase == .began {
            folderSwipeAccumulator = 0
            folderSwipeConsumed = false
        }
        if event.phase.isEmpty {
            folderSwipeAccumulator += delta
            if abs(folderSwipeAccumulator) > 40 {
                state.folderFlip(folderSwipeAccumulator > 0 ? -1 : 1)
                folderSwipeAccumulator = 0
            }
            return
        }
        guard !folderSwipeConsumed else { return }
        folderSwipeAccumulator += delta
        if abs(folderSwipeAccumulator) > 50 {
            folderSwipeConsumed = true
            state.folderFlip(folderSwipeAccumulator > 0 ? -1 : 1)
        }
    }
}