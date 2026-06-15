//
//  HotKeyController.swift
//  tab
//
//  A session-level CGEventTap that owns the trigger interaction. Unlike NSEvent
//  global monitors, an event tap can *swallow* events, so the cycle key never
//  leaks through to the focused app while the switcher is up.
//
//  The exact keys/modifier are read live from `SettingsStore`, so changing the
//  shortcut in Settings takes effect immediately — no relaunch needed.
//
//  Requires Accessibility permission. The tap is installed on the main run
//  loop, so its callback runs on the main thread.
//

import AppKit
import CoreGraphics

/// C callback for the event tap. It must be `nonisolated` (a `@convention(c)`
/// function can't carry actor isolation); we hop back onto the main actor via
/// `assumeIsolated`, which is safe because the tap lives on the main run loop.
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HotKeyController>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        controller.handle(type: type, event: event)
    }
}

@MainActor
final class HotKeyController {

    // Callbacks into the app. The controller decides *when*; the owner decides *what*.
    var onTriggerForward: (() -> Void)?    // hold-modifier + cycle key
    var onTriggerBackward: (() -> Void)?   // hold-modifier + Shift + cycle key
    var onSearch: (() -> Void)?            // hold-modifier + search key (while open)
    var onOptionReleased: (() -> Void)?    // hold modifier lifted (while cycling)
    var onCommit: (() -> Void)?            // Return key (while searching)
    var onCancel: (() -> Void)?            // Escape key (while searching)

    /// Fires when the modifier is released without the panel ever having been
    /// shown — triggers an instant switch to the next window (no UI).
    var onModifierTap: (() -> Void)?

    // State queries the owner answers.
    var isPanelVisible: () -> Bool = { false }
    var isSearching: () -> Bool = { false }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var settings: SettingsStore { .shared }

    /// Installs the tap. Returns `false` if it couldn't be created (almost
    /// always missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    /// Core event handling. Return `nil` to swallow an event, or the event
    /// (unmodified) to let it continue to the rest of the system.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // The system disables a tap that's slow or interrupted; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passthrough
        }

        let flags = event.flags
        let modifierDown = flags.contains(settings.cgModifierFlags)

        switch type {
        case .flagsChanged:
            if !modifierDown {
                if isPanelVisible() {
                    if isSearching() {
                        // Don't swallow — let the system update modifier flags so
                        // subsequent key events have the correct (unmodified) character.
                        return passthrough
                    }
                    // Cycling — commit selection and close.
                    onOptionReleased?()
                    return nil
                }
                // Modifier released without the panel ever opening.
                // In instant-switch mode, jump directly to the next window.
                if settings.instantSwitch {
                    onModifierTap?()
                    // Don't swallow — let the key-up reach the foreground app.
                }
            }
            return passthrough

        case .keyDown:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

            if isSearching() {
                // Let Tab / cycle key navigate the list while searching.
                if keyCode == settings.cycleKeyCode {
                    if flags.contains(.maskShift) {
                        onTriggerBackward?()
                    } else {
                        onTriggerForward?()
                    }
                    return nil
                }

                // Arrows (ANSI): Down/Right = forward, Up/Left = backward
                if keyCode == 125 || keyCode == 124 {
                    onTriggerForward?()
                    return nil
                }
                if keyCode == 126 || keyCode == 123 {
                    onTriggerBackward?()
                    return nil
                }

                // Commit on Return, Cancel on Escape
                if keyCode == 36 {
                    onCommit?()
                    return nil
                }
                if keyCode == 53 {
                    onCancel?()
                    return nil
                }

                return passthrough
            }

            if modifierDown, keyCode == settings.cycleKeyCode {
                if flags.contains(.maskShift) {
                    onTriggerBackward?()
                } else {
                    onTriggerForward?()
                }
                return nil
            }

            if modifierDown, keyCode == settings.searchKeyCode, isPanelVisible() {
                onSearch?()
                return nil
            }
            return passthrough

        default:
            return passthrough
        }
    }
}
