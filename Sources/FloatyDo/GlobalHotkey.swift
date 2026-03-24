import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Carbon)
import Carbon.HIToolbox
#endif

public struct GlobalHotkey: Codable, Equatable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public static let defaultToggle = GlobalHotkey(
        keyCode: UInt16(kVK_Space),
        command: false,
        option: true,
        control: true,
        shift: false
    )

    public init(
        keyCode: UInt16,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    public var isValid: Bool {
        command || option || control
    }

    public var normalized: GlobalHotkey {
        isValid ? self : .defaultToggle
    }
}

#if canImport(Carbon)
extension GlobalHotkey {
    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if command { modifiers |= UInt32(cmdKey) }
        if option { modifiers |= UInt32(optionKey) }
        if control { modifiers |= UInt32(controlKey) }
        if shift { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
#endif

#if canImport(AppKit)
extension GlobalHotkey {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hotkey = GlobalHotkey(
            keyCode: event.keyCode,
            command: modifiers.contains(.command),
            option: modifiers.contains(.option),
            control: modifiers.contains(.control),
            shift: modifiers.contains(.shift)
        )

        guard hotkey.isValid, Self.keyToken(for: event.keyCode, characters: event.charactersIgnoringModifiers) != nil else {
            return nil
        }

        self = hotkey
    }

    var displayTokens: [String] {
        var tokens: [String] = []
        if control { tokens.append("control") }
        if option { tokens.append("option") }
        if shift { tokens.append("shift") }
        if command { tokens.append("command") }
        if let key = Self.keyToken(for: keyCode, characters: nil) {
            tokens.append(key)
        }
        return tokens
    }

    var displayString: String {
        displayTokens.map(Self.displayLabel(for:)).joined(separator: " ")
    }

    private static func keyToken(for keyCode: UInt16, characters: String?) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_A:
            return "A"
        case kVK_ANSI_B:
            return "B"
        case kVK_ANSI_C:
            return "C"
        case kVK_ANSI_D:
            return "D"
        case kVK_ANSI_E:
            return "E"
        case kVK_ANSI_F:
            return "F"
        case kVK_ANSI_G:
            return "G"
        case kVK_ANSI_H:
            return "H"
        case kVK_ANSI_I:
            return "I"
        case kVK_ANSI_J:
            return "J"
        case kVK_ANSI_K:
            return "K"
        case kVK_ANSI_L:
            return "L"
        case kVK_ANSI_M:
            return "M"
        case kVK_ANSI_N:
            return "N"
        case kVK_ANSI_O:
            return "O"
        case kVK_ANSI_P:
            return "P"
        case kVK_ANSI_Q:
            return "Q"
        case kVK_ANSI_R:
            return "R"
        case kVK_ANSI_S:
            return "S"
        case kVK_ANSI_T:
            return "T"
        case kVK_ANSI_U:
            return "U"
        case kVK_ANSI_V:
            return "V"
        case kVK_ANSI_W:
            return "W"
        case kVK_ANSI_X:
            return "X"
        case kVK_ANSI_Y:
            return "Y"
        case kVK_ANSI_Z:
            return "Z"
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        case kVK_ANSI_Equal:
            return "="
        case kVK_ANSI_Minus:
            return "-"
        case kVK_ANSI_LeftBracket:
            return "["
        case kVK_ANSI_RightBracket:
            return "]"
        case kVK_ANSI_Semicolon:
            return ";"
        case kVK_ANSI_Quote:
            return "'"
        case kVK_ANSI_Comma:
            return ","
        case kVK_ANSI_Period:
            return "."
        case kVK_ANSI_Slash:
            return "/"
        case kVK_ANSI_Backslash:
            return "\\"
        case kVK_ANSI_Grave:
            return "`"
        case kVK_Space:
            return "space"
        case kVK_Return:
            return "return"
        case kVK_Delete:
            return "delete"
        case kVK_Escape:
            return "escape"
        case kVK_Tab:
            return "tab"
        case kVK_LeftArrow:
            return "left"
        case kVK_RightArrow:
            return "right"
        case kVK_UpArrow:
            return "up"
        case kVK_DownArrow:
            return "down"
        default:
            break
        }

        if let characters {
            if characters == " " {
                return "space"
            }
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count == 1 {
                return trimmed.uppercased()
            }
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    static func displayLabel(for token: String) -> String {
        switch token.lowercased() {
        case "command":
            return "⌘"
        case "control":
            return "⌃"
        case "option":
            return "⌥"
        case "shift":
            return "⇧"
        case "return":
            return "↩"
        case "delete":
            return "⌫"
        case "space":
            return "Space"
        case "escape":
            return "Esc"
        case "tab":
            return "Tab"
        case "left":
            return "←"
        case "right":
            return "→"
        case "up":
            return "↑"
        case "down":
            return "↓"
        default:
            return token
        }
    }
}
#endif
