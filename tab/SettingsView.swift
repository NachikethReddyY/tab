//
//  SettingsView.swift
//  tab
//
//  The preferences window. Each group is its own separated Liquid Glass card —
//  Shortcuts (with a live key recorder), Appearance, and About — laid out in a
//  GlassEffectContainer over a soft gradient so the glass has colour to refract.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 22) {
                VStack(spacing: 22) {
                    shortcutsCard
                    appearanceCard
                    aboutCard
                }
                .padding(28)
            }
        }
        .scrollIndicators(.never)
        .frame(width: 460, height: 640)
        .background(background)
    }

    // MARK: Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.28),
                Color.purple.opacity(0.16),
                Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    // MARK: Shortcuts

    private var shortcutsCard: some View {
        SettingsCard(title: "Shortcuts", systemImage: "command") {
            VStack(alignment: .leading, spacing: 18) {
                ModifierRecorderField(title: "Hold modifier", modifierFlags: $settings.modifierFlags)
                KeyRecorderField(title: "Cycle windows", keyCode: $settings.cycleKeyCode)
                KeyRecorderField(title: "Enter search", keyCode: $settings.searchKeyCode)

                Text("Hold \(shortModifierString(settings.cgModifierFlags)), tap \(KeyCodes.name(for: settings.cycleKeyCode)) to cycle, release to switch. Tap \(KeyCodes.name(for: settings.searchKeyCode)) to search.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Tint the selected window", isOn: $settings.useAccentTint)
                Toggle("Animate navigation", isOn: $settings.animateNavigation)

                Divider().opacity(0.15)

                Toggle(isOn: $settings.launchAtLogin) {
                    Label("Launch at login", systemImage: "power")
                }
                Toggle(isOn: $settings.instantSwitch) {
                    Label("Instant switch", systemImage: "forward.fill")
                }

            }
            .toggleStyle(.switch)
        }
    }

    // MARK: About

    private var aboutCard: some View {
        SettingsCard(title: "About", systemImage: "info.circle") {
            HStack(spacing: 16) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon).resizable()
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("tab")
                        .font(.system(size: 20, weight: .bold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("A keyboard-driven window switcher.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Reusable glass card

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

// MARK: - Key recorder

/// Tap to record; the next key press becomes the new shortcut key. Uses a local
/// event monitor so it can capture keys (like Tab) that would otherwise drive
/// keyboard navigation.
private struct KeyRecorderField: View {
    let title: String
    @Binding var keyCode: Int

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button(action: toggle) {
                Text(isRecording ? "Press a key…" : KeyCodes.name(for: keyCode))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 84)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .tint(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyCode = Int(event.keyCode)
            stop()
            return nil // swallow the captured key
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

// MARK: - Modifier recorder

/// Tap to record; the next modifier-key press sets the trigger modifier.
private struct ModifierRecorderField: View {
    let title: String
    @Binding var modifierFlags: UInt64

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button(action: toggle) {
                Text(isRecording ? "Press modifier…" : shortModifierString(CGEventFlags(rawValue: modifierFlags)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 84)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .tint(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
        }
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            let nsFlags = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            guard !nsFlags.isEmpty else { return event }
            // Convert NSEvent.ModifierFlags → CGEventFlags (different raw values).
            var cg: CGEventFlags = []
            if nsFlags.contains(.control)  { cg.insert(.maskControl) }
            if nsFlags.contains(.option)   { cg.insert(.maskAlternate) }
            if nsFlags.contains(.command)  { cg.insert(.maskCommand) }
            if nsFlags.contains(.shift)    { cg.insert(.maskShift) }
            if nsFlags.contains(.function) { cg.insert(.maskSecondaryFn) }
            modifierFlags = cg.rawValue
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
