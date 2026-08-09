import AppKit
import SwiftUI
import launchPadCore

/// Owns the first-launch onboarding window. It closes automatically once
/// Accessibility is granted and marks onboarding as completed whenever the
/// user dismisses it, so it does not nag on every launch.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var pendingAutoClose = false

    func open() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "launchPad"
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        pendingAutoClose = false
        refreshContentView()
        // orderFrontRegardless is what actually puts the window on screen even
        // when the app was launched from a non-GUI context and cannot activate.
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        pendingAutoClose = false
        AppSettings.hasCompletedOnboarding = true
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppSettings.hasCompletedOnboarding = true
    }

    /// Recreates the hosting view on every open so the guide always starts
    /// with a fresh permission state.
    private func refreshContentView() {
        window?.contentView = NSHostingView(rootView: OnboardingView(
            onPermissionGranted: { [weak self] in
                self?.scheduleAutoClose()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        ))
    }

    /// Lets the success state show briefly before closing the guide.
    private func scheduleAutoClose() {
        guard !pendingAutoClose else { return }
        pendingAutoClose = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.close()
        }
    }
}
