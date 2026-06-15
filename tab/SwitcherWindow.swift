//
//  SwitcherWindow.swift
//  tab
//
//  One switchable window. The switcher is window-level: a row per open window,
//  showing its title so you can pick the exact window — across apps and Spaces.
//

import AppKit
import ApplicationServices
import CoreGraphics

/// A lightweight, value-type description of an open window.
///
/// `element` is the matching `AXUIElement` (used to raise the window and read
/// its title); it may be `nil` for windows with no Accessibility handle.
struct SwitcherWindow: Identifiable {
    let id: String
    let pid: pid_t
    let windowID: CGWindowID
    let element: AXUIElement?
    let title: String
    let appName: String
    let icon: NSImage?

    /// Primary line: the window's title (falls back to the app name).
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    /// Text the fuzzy matcher searches against (app name + window title).
    var searchableText: String {
        title.isEmpty ? appName : "\(appName) \(title)"
    }
}
