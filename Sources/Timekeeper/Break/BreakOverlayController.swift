import AppKit
import SwiftUI

/// Borderless windows have no key status by default, which would make the buttons unresponsive.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the blurred break screen on every display, above everything including full-screen apps.
@MainActor
final class BreakOverlayController {
    private var windows: [NSWindow] = []

    func show(model: AppModel) {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false

            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)

            let host = NSHostingView(rootView: BreakView(model: model))
            host.autoresizingMask = [.width, .height]
            host.frame = blur.bounds
            blur.addSubview(host)

            window.contentView = blur
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
