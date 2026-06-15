//
//  tabApp.swift
//  tab
//
//  Created by Nachiketh Reddy on 15/6/26.
//

import AppKit
import SwiftUI

@main
struct tabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A persistent menu-bar item. Being a real scene, this is what keeps the
        // background app alive — a Settings-only app launches and immediately
        // quits, which is why the menu-bar icon used to flash and vanish.
        MenuBarExtra("tab", systemImage: "rectangle.on.rectangle") {
            MenuContent(appDelegate: appDelegate)
        }
    }
}

private struct MenuContent: View {
    let appDelegate: AppDelegate
    @State private var settings = SettingsStore.shared

    var body: some View {
        Text("\(settings.triggerDescription)  Switch windows")
        Text("\(settings.searchDescription)  Search")

        Divider()

        Button("Settings…") { appDelegate.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Check Accessibility Permission…") { appDelegate.refreshPermissionCheck() }
        Button("Open Accessibility Settings…") { appDelegate.openAccessibilitySettings() }
        Divider()

        Button("Quit tab") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
