import AppKit
import Carbon.HIToolbox

/// 修飾キー。ビットの並びは Windows 版 (Ctrl=1, Shift=2, Alt=4, Win=8) に合わせてある。
struct Mods: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let control = Mods(rawValue: 1)
    static let shift = Mods(rawValue: 2)
    static let option = Mods(rawValue: 4)
    static let command = Mods(rawValue: 8)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: CGEventFlags) {
        var mods: Mods = []
        if flags.contains(.maskControl) { mods.insert(.control) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskCommand) { mods.insert(.command) }
        self = mods
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var mods: Mods = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        self = mods
    }

    /// Mac の並び順 (⌃⌥⇧⌘) の記号。
    var symbols: [String] {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts
    }
}

/// パターンの発動条件。通常は「修飾キー + 普通のキー」。keyCode の値で次の特別な意味を持つ:
/// - 修飾キー: そのキーだけを押して離した (mods は空)
/// - `mouseBase` 以降: 修飾キー + クリック
/// - `anyKey`: 修飾キー + 何かのキー (mods は必ず 1 つ以上)
///
/// keyCode は macOS の仮想キーコード (kVK_*)。A が 0 なので、特別な値は 0x7F より上に置く。
struct KeyTrigger: Hashable, Codable, CustomStringConvertible {
    var mods: Mods
    var keyCode: UInt16

    static let anyKey: UInt16 = 0xFFFF
    static let mouseBase: UInt16 = 0x1000 // + NSEvent.buttonNumber (0 左, 1 右, 2 中, 3 戻る, 4 進む)
    static let mouseButtonCount = 5

    /// 修飾キーのキーコードと、それに対応する修飾キー・左右を区別するフラグ (NX_DEVICE*KEYMASK)。
    static let modifierKeys: [UInt16: (mod: Mods, deviceFlag: UInt64)] = [
        0x3B: (.control, 0x0000_0001), 0x3E: (.control, 0x0000_2000),
        0x38: (.shift, 0x0000_0002), 0x3C: (.shift, 0x0000_0004),
        0x3A: (.option, 0x0000_0020), 0x3D: (.option, 0x0000_0040),
        0x37: (.command, 0x0000_0008), 0x36: (.command, 0x0000_0010),
    ]

    static func mouse(_ buttonNumber: Int, mods: Mods) -> KeyTrigger? {
        guard (0..<mouseButtonCount).contains(buttonNumber) else { return nil }
        return KeyTrigger(mods: mods, keyCode: mouseBase + UInt16(buttonNumber))
    }

    /// 左右の区別をなくす (右 Shift → 左 Shift など)。
    static func normalize(_ keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 0x3C: 0x38
        case 0x3E: 0x3B
        case 0x3D: 0x3A
        case 0x36: 0x37
        default: keyCode
        }
    }

    static func modOf(_ keyCode: UInt16) -> Mods { modifierKeys[keyCode]?.mod ?? [] }

    var isModifierOnly: Bool { Self.modifierKeys[keyCode] != nil }

    var isMouse: Bool { keyCode >= Self.mouseBase && keyCode < Self.mouseBase + UInt16(Self.mouseButtonCount) }

    var description: String { (mods.symbols + [Self.keyName(keyCode)]).joined(separator: " + ") }

    static func keyName(_ keyCode: UInt16) -> String {
        switch modOf(keyCode) {
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        default: break
        }
        if keyCode == anyKey { return "任意のキー" }
        if keyCode >= mouseBase {
            let names = ["左クリック", "右クリック", "中クリック", "サイドボタン (戻る)", "サイドボタン (進む)"]
            let index = Int(keyCode - mouseBase)
            return index < names.count ? names[index] : "マウスボタン \(index + 1)"
        }
        return specialKeyNames[keyCode] ?? typedName(keyCode) ?? String(format: "0x%02X", keyCode)
    }

    private static let specialKeyNames: [UInt16: String] = [
        0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete", 0x35: "Esc", 0x75: "⌦ Delete",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x73: "Home", 0x77: "End", 0x74: "PageUp", 0x79: "PageDown", 0x72: "Help",
        0x66: "英数", 0x68: "かな",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        0x52: "Num0", 0x53: "Num1", 0x54: "Num2", 0x55: "Num3", 0x56: "Num4",
        0x57: "Num5", 0x58: "Num6", 0x59: "Num7", 0x5B: "Num8", 0x5C: "Num9",
        0x41: "Num.", 0x43: "Num*", 0x45: "Num+", 0x47: "Clear", 0x4B: "Num/", 0x4C: "Enter", 0x4E: "Num-", 0x51: "Num=",
    ]

    /// 今のキーボード配列でそのキーが打つ文字 (A, 1, ; など)。
    private static func typedName(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                           keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).uppercased()
        return text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : text
    }
}

final class Pattern: Codable {
    var trigger: KeyTrigger
    var image: String?

    init(trigger: KeyTrigger, image: String?) {
        self.trigger = trigger
        self.image = image
    }
}
