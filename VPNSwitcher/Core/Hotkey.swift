import Foundation

/// Un atajo de teclado global declarado en profiles.yaml, p. ej.
/// "cmd+opt+1" o "ctrl+shift+f5". Lógica pura (sin Carbon) para poder
/// testearla; el registro real lo hace HotkeyManager.
struct Hotkey: Hashable, Sendable {
    /// Keycode virtual del layout ANSI (posicional, como kVK_ANSI_*).
    let keyCode: UInt32
    /// Máscara de modificadores en formato Carbon (cmdKey, optionKey…).
    let carbonModifiers: UInt32
    /// Representación para la UI: "⌘⌥1".
    let display: String

    // Valores de Carbon (Events.h), copiados para no arrastrar el import.
    private static let cmd: UInt32 = 0x0100
    private static let shift: UInt32 = 0x0200
    private static let option: UInt32 = 0x0800
    private static let control: UInt32 = 0x1000

    /// Formato: modificadores y tecla separados por "+". Modificadores:
    /// cmd/command, opt/option/alt, ctrl/control, shift. Tecla: letra,
    /// dígito, "space" o F1–F12. Exige al menos un modificador que no sea
    /// shift: un atajo global de solo-shift secuestraría la escritura normal.
    init?(parsing text: String) {
        let tokens = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard tokens.count >= 2, let keyToken = tokens.last,
              let keyCode = Self.keyCodes[keyToken] else { return nil }

        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command", "⌘": modifiers |= Self.cmd
            case "opt", "option", "alt", "⌥": modifiers |= Self.option
            case "ctrl", "control", "⌃": modifiers |= Self.control
            case "shift", "⇧": modifiers |= Self.shift
            default: return nil
            }
        }
        guard modifiers & ~Self.shift != 0 else { return nil }

        self.keyCode = keyCode
        self.carbonModifiers = modifiers

        var symbols = ""
        if modifiers & Self.control != 0 { symbols += "⌃" }
        if modifiers & Self.option != 0 { symbols += "⌥" }
        if modifiers & Self.shift != 0 { symbols += "⇧" }
        if modifiers & Self.cmd != 0 { symbols += "⌘" }
        self.display = symbols + (keyToken == "space" ? "Space" : keyToken.uppercased())
    }

    /// Keycodes virtuales ANSI (posicionales, independientes de si el
    /// layout es español o no a efectos de registro).
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25, "0": 29,
        "space": 49,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
