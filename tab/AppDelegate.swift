//
//  AppDelegate.swift
//  tab
//
//  Installs the global hotkey tap and owns the floating switcher panel and the
//  preferences window. The menu-bar presence itself lives in `tabApp`'s
//  `MenuBarExtra` scene — that scene is what keeps this background app alive.
//

import AppKit
import QuartzCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let viewModel = SwitcherViewModel()
    private let hotKeys = HotKeyController()

    private var panel: SwitcherPanel?
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private var didWarnAboutSandbox = false
    /// Track whether the Accessibility event tap is running.
    private(set) var permissionGranted = false
    /// PID of the app that was frontmost before we activated tab for search.
    private var previousAppPID: pid_t?

    /// Fixed panel width; height is computed per-screen so the list fills
    /// the middle 60% (between 20% and 80% of the screen's visible area).
    private let panelWidth: CGFloat = 544

    // MARK: Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No Dock icon, no app-switcher entry — a background utility. The
        // MenuBarExtra scene keeps the process running.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureHotKeys()
        startTrackingAppActivations()
        WindowManager.refreshCache()
        beginPermissionPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
        permissionTimer?.invalidate()
    }

    // Never quit just because no window is open — this is a menu-bar agent.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Permission

    private func startTapOrWarn() {
        if !hotKeys.start() {
            // Trusted for Accessibility but the tap still failed — almost always
            // means the App Sandbox is still enabled for this target.
            presentSandboxWarning()
        }
    }

    /// Silently poll for Accessibility permission every 2s.
    /// When granted, start the event tap and mark the state.
    private func beginPermissionPolling() {
        // Check once synchronously first — fast path if already trusted.
        if WindowManager.hasAccessibilityPermission(prompt: false) {
            permissionGranted = true
            startTapOrWarn()
            return
        }

        permissionGranted = false
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard WindowManager.hasAccessibilityPermission(prompt: false) else { return }
                timer.invalidate()
                self.permissionTimer = nil
                self.permissionGranted = true
                self.startTapOrWarn()
            }
        }
    }

    /// Explicit re-check, callable from the menu bar.
    @objc func refreshPermissionCheck() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        beginPermissionPolling()
        // If still not granted, show the guidance alert.
        if !permissionGranted {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "tab needs Accessibility access"
            alert.informativeText = """
            To switch windows, tab needs permission to monitor your keyboard and windows.

            Please open System Settings → Privacy & Security → Accessibility,
            find “tab” in the list and switch it ON.
            """
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }
    }

    private func presentSandboxWarning() {
        guard !didWarnAboutSandbox else { return }
        didWarnAboutSandbox = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t start the global shortcut"
        alert.informativeText = """
        tab needs the App Sandbox turned off to capture \(SettingsStore.shared.triggerDescription) shortcuts system-wide.

        In Xcode: select the tab target → Build Settings → set “App Sandbox” to No, then run again.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: Hotkey wiring

    private func configureHotKeys() {
        hotKeys.isPanelVisible = { [weak self] in self?.panel?.isVisible ?? false }
        hotKeys.isSearching = { [weak self] in self?.viewModel.isSearching ?? false }
        hotKeys.onTriggerForward = { [weak self] in self?.handleTrigger(forward: true) }
        hotKeys.onTriggerBackward = { [weak self] in self?.handleTrigger(forward: false) }
        hotKeys.onSearch = { [weak self] in self?.beginSearch() }
        hotKeys.onOptionReleased = { [weak self] in self?.commitAndClose() }
        hotKeys.onCommit = { [weak self] in self?.commitAndClose() }
        hotKeys.onCancel = { [weak self] in
            self?.closePanel()
            self?.reactivatePreviousApp()
        }
        hotKeys.onModifierTap = { [weak self] in self?.instantSwitch() }
    }

    /// Trigger: open the switcher (first press) or advance the selection.
    private func handleTrigger(forward: Bool) {
        if panel?.isVisible == true {
            forward ? viewModel.cycleForward() : viewModel.cycleBackward()
            return
        }

        // Fast path: if the cache is already warm, the panel opens instantly.
        let apps = WindowManager.fetchWindows()
        guard !apps.isEmpty else { return }
        viewModel.begin(with: apps)
        showPanel()
    }

    /// Instant-switch: press and release the modifier (no Tab tap) to jump
    /// directly to the most-recently-used window — no panel shown.
    private func instantSwitch() {
        let apps = WindowManager.fetchWindows()
        guard apps.count >= 2 else { return }
        // Index 0 = current app, index 1 = next MRU (mirrors Cmd+Tab).
        let target = apps[1]
        WindowManager.activate(target)
    }

    /// Search key: switch into search mode and grab keyboard focus so the field
    /// receives typing. (Releasing the modifier no longer closes the panel.)
    ///
    /// We make the panel key *before* flipping into search mode so the text
    /// field reliably becomes first responder in an already-key window.
    private func beginSearch() {
        guard panel?.isVisible == true else { return }

        // Only track the previous app if we aren't already searching; otherwise,
        // we'd accidentally track 'tab' itself as the previous app.
        if !viewModel.isSearching {
            previousAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            viewModel.enterSearch()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: App activation tracking (drives MRU order)

    private func startTrackingAppActivations() {
        // Seed with whatever's frontmost right now.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            WindowManager.noteAppActivated(pid)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        WindowManager.noteAppActivated(app.processIdentifier)
    }

    // MARK: Panel lifecycle

    private func showPanel() {
        let panel = panelOrCreated()
        resizePanelToFitScreen(panel)
        centerInMiddleBand(panel)
        panel.orderFrontRegardless()
    }

    /// Height so the switcher fills the middle 60% of the active screen.
    private func panelHeightForCurrentScreen() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return SwitcherView.idealPanelHeight(for: screen)
    }

    private func resizePanelToFitScreen(_ panel: SwitcherPanel) {
        let height = panelHeightForCurrentScreen()
        let size = NSSize(width: panelWidth, height: height)
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
        if let view = panel.contentView {
            view.frame = NSRect(origin: .zero, size: size)
        }
    }

    /// Position the panel vertically so it sits in the middle 60% of the screen
    /// (20% inset from top, 20% from bottom), horizontally centered.
    private func centerInMiddleBand(_ panel: SwitcherPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.2    // 20% from bottom
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func panelOrCreated() -> SwitcherPanel {
        if let panel { return panel }

        let root = SwitcherView(
            viewModel: viewModel,
            onCommit: { [weak self] in self?.commitAndClose() },
            onCancel: { [weak self] in
                self?.closePanel()
                self?.reactivatePreviousApp()
            }
        )
        let hosting = NSHostingView(rootView: root)

        let height = panelHeightForCurrentScreen()
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: height))

        let created = SwitcherPanel(contentView: hosting)
        panel = created
        return created
    }

    /// Dismiss, then activate the selected window (closing first keeps the panel
    /// from lingering during the Space-switch animation).
    private func commitAndClose() {
        let window = viewModel.selectedWindow
        closePanel()
        if let window {
            WindowManager.activate(window)
        }
    }

    /// Hide the panel and reset state. The panel instance is kept and reused.
    private func closePanel() {
        panel?.orderOut(nil)
        viewModel.reset()
    }

    /// Reactivate the app that was frontmost before search began.
    private func reactivatePreviousApp() {
        guard let pid = previousAppPID else { return }
        previousAppPID = nil
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: Menu actions (invoked from the MenuBarExtra)

    /// Lazily builds and shows the preferences window.
    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "tab — Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Guide the user to manually remove and re-add tab in System Settings,
    /// which resets the permission for *only this app* (unlike `tccutil reset Accessibility`
    /// which resets every app's permission).
    func resetPermissionsForThisApp() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Reset tab’s permission"
        alert.informativeText = """
        To fix a stuck permission:

        1. Click "Open Settings" below.
        2. In the list, find "tab" and remove it with the − button.
        3. Quit and relaunch tab — it will ask again.

        This only affects tab, not your other apps.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
