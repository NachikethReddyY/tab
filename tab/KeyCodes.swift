//
//  KeyCodes.swift
//  tab
//
//  Maps macOS virtual key codes to human-readable names for the shortcut
//  recorder UI. Covers the common ANSI keyboard; unknown codes fall back to a
//  numeric label.
//

import Foundation

enum KeyCodes {

    /// A short, display-ready name for a virtual key code (e.g. "Tab", "S", "␣").
    static func name(for code: Int) -> String {
        names[code] ?? "Key \(code)"
    }

    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "␣", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
