//
//  WindowManager.swift
//  tab
//
//  Enumerates and activates individual windows across ALL Spaces/Desktops.
//
//  The authoritative window set comes from CoreGraphics' window list with
//  `.optionAll` (spans every Space; needs no Screen Recording permission). Each
//  window is matched to its Accessibility element via its CGWindowID to get a
//  reliable title and a raise handle. Only titled, reasonably-sized, normal
//  windows are kept, which filters out helper/utility "ghost" windows.
//
//  Ordering: windows we've recently switched to come first (precise MRU), then
//  the rest grouped by most-recently-used app, then everything else.
//

import AppKit
import ApplicationServices
import CoreGraphics

/// Private AppKit bridge: maps an Accessibility window element to its CGWindowID.
/// Same mechanism used by window managers like AltTab to correlate the
/// Accessibility and CoreGraphics views of a window.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowManager {

    // MARK: Permission (needed for the event tap and AX titles)

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Most-recently-used ordering

    /// App process ids, most-recently-activated first (groups an app's windows).
    private static var recentAppPIDs: [pid_t] = []
    /// Window ids, most-recently-activated first (precise per-window order).
    private static var recentWindowIDs: [CGWindowID] = []

    static func noteAppActivated(_ pid: pid_t) {
        recentAppPIDs.removeAll { $0 == pid }
        recentAppPIDs.insert(pid, at: 0)
        if recentAppPIDs.count > 64 { recentAppPIDs.removeLast(recentAppPIDs.count - 64) }
        // MRU changed — refresh the cache silently
        refreshCache()
    }

    private static func noteWindowActivated(_ windowID: CGWindowID) {
        recentWindowIDs.removeAll { $0 == windowID }
        recentWindowIDs.insert(windowID, at: 0)
        if recentWindowIDs.count > 128 { recentWindowIDs.removeLast(recentWindowIDs.count - 128) }
    }

    // MARK: Background cache (so the panel opens instantly)

    /// Pre-fetched window list, refreshed in the background.
    private static var cachedWindows: [SwitcherWindow] = []
    private static var cacheIsStale = true

    /// Return the cached list (or fetch if stale / first call).
    static func fetchWindows() -> [SwitcherWindow] {
        if cacheIsStale {
            cachedWindows = buildWindowList()
            cacheIsStale = false
        }
        return cachedWindows
    }

    /// Rebuild the cache in the background (call after app activation).
    static func refreshCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = buildWindowList()
            DispatchQueue.main.async {
                cachedWindows = fresh
                cacheIsStale = false
            }
        }
    }

    /// Mark stale so the next `fetchWindows()` rebuilds.
    static func invalidateCache() {
        cacheIsStale = true
    }

    /// The actual enumeration logic (unchanged).
    private static func buildWindowList() -> [SwitcherWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Cache per-pid lookups so each app is queried at most once.
        var axByPID: [pid_t: [CGWindowID: (element: AXUIElement, title: String)]] = [:]
        var appByPID: [pid_t: NSRunningApplication] = [:]

        // Keep CoreGraphics' front-to-back order as a stable tiebreaker.
        var entries: [(window: SwitcherWindow, order: Int)] = []
        var order = 0

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            // Drop small panels / ghost windows.
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               bounds.width < 120 || bounds.height < 90 {
                continue
            }

            let app: NSRunningApplication
            if let cached = appByPID[pid] {
                app = cached
            } else if let resolved = NSRunningApplication(processIdentifier: pid) {
                app = resolved
                appByPID[pid] = resolved
            } else {
                continue
            }
            guard app.activationPolicy == .regular, !app.isTerminated else { continue }

            let axWindows = axByPID[pid] ?? {
                let built = buildAXWindowMap(for: pid)
                axByPID[pid] = built
                return built
            }()
            let match = axWindows[windowID]

            let cgName = info[kCGWindowName as String] as? String ?? ""
            let title = (match?.title.isEmpty == false) ? (match?.title ?? "") : cgName

            // Clutter filter: only keep windows we can actually name.
            guard !title.isEmpty else { continue }

            let window = SwitcherWindow(
                id: String(windowID),
                pid: pid,
                windowID: windowID,
                element: match?.element,
                title: title,
                appName: app.localizedName ?? "Unknown",
                icon: app.icon
            )
            entries.append((window, order))
            order += 1
        }

        entries.sort {
            sortKey($0.window, order: $0.order, frontmostPID: frontmostPID)
                < sortKey($1.window, order: $1.order, frontmostPID: frontmostPID)
        }
        return entries.map(\.window)
    }

    /// Sort key: recently-used windows first, then frontmost app, then recent
    /// apps, then everything else; CoreGraphics order breaks ties.
    private static func sortKey(_ window: SwitcherWindow, order: Int, frontmostPID: pid_t?) -> (Int, Int, Int) {
        if let index = recentWindowIDs.firstIndex(of: window.windowID) {
            return (0, index, order)
        }
        let appRank: Int
        if window.pid == frontmostPID {
            appRank = -1
        } else if let index = recentAppPIDs.firstIndex(of: window.pid) {
            appRank = index
        } else {
            appRank = Int.max
        }
        return (1, appRank, order)
    }

    /// Builds a `CGWindowID → (element, title)` map for one application.
    private static func buildAXWindowMap(for pid: pid_t) -> [CGWindowID: (element: AXUIElement, title: String)] {
        let appElement = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success,
              let axWindows = raw as? [AXUIElement] else {
            return [:]
        }

        var map: [CGWindowID: (AXUIElement, String)] = [:]
        for window in axWindows {
            var windowID: CGWindowID = 0
            guard _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 else { continue }
            map[windowID] = (window, copyStringAttribute(window, kAXTitleAttribute))
        }
        return map
    }

    // MARK: Activation

    /// Raises the specific window and focuses its app. Raising a window on
    /// another Space makes macOS switch to that Space.
    static func activate(_ window: SwitcherWindow) {
        if let element = window.element {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        noteWindowActivated(window.windowID)
        noteAppActivated(window.pid)
    }

    // MARK: AX helpers

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let string = value as? String else { return "" }
        return string
    }
}
