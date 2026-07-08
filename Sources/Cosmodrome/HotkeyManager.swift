import AppKit
import Carbon.HIToolbox
import CosmodromeCore

/// System-wide hotkey via Carbon's RegisterEventHotKey — still the only way
/// to grab a global shortcut without Accessibility permissions.
final class HotkeyManager {
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = CarbonModifiers.option // ⌥Space

    var onHotkey: () -> Void = {}

    private(set) var keyCode: UInt32 = HotkeyManager.defaultKeyCode
    private(set) var modifiers: UInt32 = HotkeyManager.defaultModifiers
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var displayString: String {
        KeyNames.displayString(keyCode: keyCode, carbonModifiers: modifiers)
    }

    func loadAndRegister() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            keyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            modifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        }
        register()
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "hotkeyKeyCode")
        defaults.set(Int(modifiers), forKey: "hotkeyModifiers")
        register()
    }

    /// Carbon consumes a registered hotkey before it can reach the shortcut
    /// recorder as an NSEvent, so the recorder suspends it while armed.
    func setSuspended(_ suspended: Bool) {
        if suspended {
            unregister()
        } else {
            register()
        }
    }

    @discardableResult
    private func register() -> Bool {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x43_53_4D_44), id: 1) // 'CSMD'
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr {
            hotKeyRef = ref
            return true
        }
        NSLog("Cosmodrome: RegisterEventHotKey failed (%d) — shortcut may be taken", status)
        return false
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onHotkey() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
