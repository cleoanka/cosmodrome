import Foundation

/// Carbon modifier masks, mirrored so the pure core needs no Carbon import.
public enum CarbonModifiers {
    public static let command: UInt32 = 1 << 8   // cmdKey
    public static let shift: UInt32 = 1 << 9     // shiftKey
    public static let option: UInt32 = 1 << 11   // optionKey
    public static let control: UInt32 = 1 << 12  // controlKey
}

/// Human-readable names for keyboard shortcuts (⌥Space, ⌃⌘L, F4, …).
public enum KeyNames {
    public static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        modifierSymbols(carbonModifiers) + keyName(for: keyCode)
    }

    public static func modifierSymbols(_ mods: UInt32) -> String {
        var s = ""
        if mods & CarbonModifiers.control != 0 { s += "⌃" }
        if mods & CarbonModifiers.option != 0 { s += "⌥" }
        if mods & CarbonModifiers.shift != 0 { s += "⇧" }
        if mods & CarbonModifiers.command != 0 { s += "⌘" }
        return s
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]

    public static func keyName(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
