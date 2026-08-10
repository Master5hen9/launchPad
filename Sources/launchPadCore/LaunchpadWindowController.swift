import AppKit
import QuartzCore
import SwiftUI

/// Owns the fullscreen, blurred overlay window that acts as the Launchpad.
@MainActor
public final class LaunchpadWindowController: NSObject {
    private var window: LaunchpadWindow?
    private var lastFrontmostApp: NSRunningApplication?
    private var previousFrontmostApp: NSRunningApplication?
    public private(set) var isOpen = false
    /// True while the overlay is visible (including the brief close fade), so
    /// the gesture monitor swallows four-or-more-finger events and the system
    /// cannot fire its own bindings (Show Desktop, etc.) at the same time.
    public private(set) var isConsumingGestures = false
    /// Invoked after the overlay has closed because the user requested
    /// Settings (Cmd+,). Set by the app delegate so opening Settings does not
    /// depend on the app menu's key-equivalent routing.
    public var onOpenSettings: (() -> Void)?

    override public init() {
        super.init()
        // Remember the most recently activated app other than ourselves, so we
        // can hand activation back after closing even when opening was triggered
        // by a Dock click (which activates us before we get to record anything).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastFrontmostApp = app
    }

    public func open() {
        guard !isOpen else {
            Diagnostics.log("open() skipped: already open")
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = frontmost ?? lastFrontmostApp
        } else {
            previousFrontmostApp = lastFrontmostApp
        }
        Diagnostics.log("open: previous frontmost=\(previousFrontmostApp?.localizedName ?? "nil")")

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let window = LaunchpadWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.title = "launchPad"
        window.appearance = NSAppearance(named: .darkAqua)

        let blurView = NSVisualEffectView()
        blurView.material = .fullScreenUI
        blurView.blendingMode = .behindWindow
        blurView.state = .active

        let hostingView = NSHostingView(rootView: LaunchpadView(
            onDismiss: { [weak self] in
                self?.close()
            },
            onOpenSettings: { [weak self] in
                guard let self else { return }
                // The Settings window takes over, so do not hand activation
                // back to the app that was frontmost before the Launchpad.
                self.close(restoringActivation: false)
                self.onOpenSettings?()
            },
            screenSize: screen.frame.size
        ))
        hostingView.frame = blurView.bounds
        hostingView.autoresizingMask = [.width, .height]
        blurView.addSubview(hostingView)
        window.contentView = blurView

        self.window = window
        isOpen = true
        isConsumingGestures = true

        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    public func close(restoringActivation: Bool = true) {
        guard isOpen, let window else {
            Diagnostics.log("close() skipped: not open")
            return
        }
        isOpen = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                self.isConsumingGestures = false
                if restoringActivation {
                    self.restoreFrontmostApp()
                }
            }
        }
    }

    public func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    /// Hands activation back to the app that was frontmost before the
    /// Launchpad opened. Without this, launchPad stays frontmost after closing
    /// and the global event monitor stops receiving pinch events, so the
    /// gesture only works the first time.
    private func restoreFrontmostApp() {
        defer { previousFrontmostApp = nil }
        guard let previous = previousFrontmostApp else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard NSApp.isActive,
              frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            Diagnostics.log("close: not frontmost anymore, skip yield")
            return
        }

        Diagnostics.log("close: yielding activation to \(previous.localizedName ?? previous.bundleIdentifier ?? "?")")
        NSApp.yieldActivation(to: previous)
        previous.activate(options: [.activateAllWindows])
        Diagnostics.log("close: frontmost now=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
    }
}

private final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
