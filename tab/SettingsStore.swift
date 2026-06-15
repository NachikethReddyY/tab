//
//  SettingsStore.swift
//  tab
//
//  User-configurable preferences, observed by the UI and the hotkey tap and
//  persisted to UserDefaults. A single shared instance is the source of truth.
//

import AppKit
import CoreGraphics
import Foundation
import Observation
import ServiceManagement

/// Human-readable description of a single modifier flag.
func labelForModifierFlag(_ flag: CGEventFlags) -> String {
    switch flag {
    case .maskAlternate: "⌥ Option"
    case .maskControl:   "⌃ Control"
    case .maskCommand:   "⌘ Command"
    case .maskShift:     "⇧ Shift"
    case .maskSecondaryFn: "fn"
    default: "?"
    }
}

/// Returns a short display string for a combined set of flags, e.g. "⌃⌥".
func shortModifierString(_ flags: CGEventFlags) -> String {
    var parts = ""
    if flags.contains(.maskControl)  { parts += "⌃" }
    if flags.contains(.maskAlternate) { parts += "⌥" }
    if flags.contains(.maskCommand)  { parts += "⌘" }
    if flags.contains(.maskShift)    { parts += "⇧" }
    return parts.isEmpty ? "?" : parts
}

@MainActor
@Observable
final class SettingsStore {

    static let shared = SettingsStore()

    /// Raw value of the CGEventFlags the user must hold. Stored as UInt64 so any
    /// combination of modifier keys is supported (Option, Control, Command, Shift, fn…).
    var modifierFlags: UInt64 {
        didSet { defaults.set(modifierFlags, forKey: Keys.modifierFlags) }
    }

    /// Virtual key code that cycles the selection (default Tab = 48).
    var cycleKeyCode: Int {
        didSet { defaults.set(cycleKeyCode, forKey: Keys.cycleKeyCode) }
    }

    /// Virtual key code that enters search mode (default S = 1).
    var searchKeyCode: Int {
        didSet { defaults.set(searchKeyCode, forKey: Keys.searchKeyCode) }
    }

    /// Tint the selected card with the accent colour.
    var useAccentTint: Bool {
        didSet { defaults.set(useAccentTint, forKey: Keys.useAccentTint) }
    }

    /// Animate selection movement and list changes (turn off for instant switching).
    var animateNavigation: Bool {
        didSet { defaults.set(animateNavigation, forKey: Keys.animateNavigation) }
    }

    /// Launch at login via SMAppService (macOS 13+).
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    /// Instant-switch mode: press + release the modifier (without pressing the
    /// cycle key) to jump directly to the next window — no panel shown.
    var instantSwitch: Bool {
        didSet { defaults.set(instantSwitch, forKey: Keys.instantSwitch) }
    }

    // MARK: Derived helpers

    /// The current modifier flags as a CGEventFlags.
    var cgModifierFlags: CGEventFlags { CGEventFlags(rawValue: modifierFlags) }

    /// e.g. "⌥Tab" — used in hints and menu titles.
    var triggerDescription: String {
        shortModifierString(cgModifierFlags) + KeyCodes.name(for: cycleKeyCode)
    }

    /// e.g. "⌥S" — used in the search hint.
    var searchDescription: String {
        shortModifierString(cgModifierFlags) + KeyCodes.name(for: searchKeyCode)
    }

    // MARK: Persistence

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let modifierFlags = "modifierFlags"
        static let cycleKeyCode = "cycleKeyCode"
        static let searchKeyCode = "searchKeyCode"
        static let useAccentTint = "useAccentTint"
        static let animateNavigation = "animateNavigation"
        static let launchAtLogin = "launchAtLogin"
        static let instantSwitch = "instantSwitch"
    }

    private init() {
        modifierFlags = defaults.object(forKey: Keys.modifierFlags) as? UInt64 ?? CGEventFlags.maskAlternate.rawValue
        cycleKeyCode = defaults.object(forKey: Keys.cycleKeyCode) as? Int ?? 48
        searchKeyCode = defaults.object(forKey: Keys.searchKeyCode) as? Int ?? 1
        useAccentTint = defaults.object(forKey: Keys.useAccentTint) as? Bool ?? true
        animateNavigation = defaults.object(forKey: Keys.animateNavigation) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        instantSwitch = defaults.object(forKey: Keys.instantSwitch) as? Bool ?? true
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(launchAtLogin ? "register" : "unregister") login item: \(error)")
        }
    }
}
