//
//  SwitcherPanel.swift
//  tab
//
//  The floating, borderless panel that hosts the SwiftUI switcher UI. It's a
//  non-activating panel so showing it during "cycling" mode doesn't steal focus
//  from the app you're switching away from — but it *can* become key on demand
//  (when search mode starts) so the text field can receive typing.
//

import AppKit

final class SwitcherPanel: NSPanel {

    init(contentView: NSView) {
        super.init(
            contentRect: contentView.bounds,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    // Allow keyboard focus (needed for the search field) without forcing it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Centres the panel on the screen currently under the pointer.
    func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrameOrigin(origin)
    }
}
