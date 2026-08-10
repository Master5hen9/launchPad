import AppKit
import SwiftUI

/// Owns the Settings window. It is presented as a plain AppKit window instead
/// of relying on the SwiftUI `Settings` scene, whose window does not reliably
/// appear in this accessory (menu-bar) app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func open() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = NSLocalizedString("launchPad 设置", comment: "Settings window title")
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        // Recreate the hosting view each time so on-screen state (hidden apps,
        // accessibility status, login-item status) is fresh.
        window?.contentView = NSHostingView(rootView: SettingsView())
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Settings are persisted on change; nothing to do on close.
    }
}
