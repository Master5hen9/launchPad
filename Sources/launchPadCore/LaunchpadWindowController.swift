import AppKit
import QuartzCore
import SwiftUI

/// Owns the fullscreen, blurred overlay window that acts as the Launchpad.
@MainActor
public final class LaunchpadWindowController: NSObject {
    private var window: LaunchpadWindow?
    private weak var hostingView: NSView?
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
            }
        ))
        hostingView.frame = blurView.bounds
        hostingView.autoresizingMask = [.width, .height]
        blurView.addSubview(hostingView)
        self.hostingView = hostingView
        window.contentView = blurView

        self.window = window
        isOpen = true
        isConsumingGestures = true

        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Diagnostics.log("open: requesting key/activation")

        animateOverlay(of: window, open: true)
    }

    public func close(restoringActivation: Bool = true) {
        guard isOpen, let window else {
            Diagnostics.log("close() skipped: not open")
            return
        }
        isOpen = false

        animateOverlay(of: window, open: false) {
            Task { @MainActor in
                window.orderOut(nil)
                window.contentView?.layer?.opacity = 1
                self.hostingView?.layer?.transform = CATransform3DIdentity
                self.isConsumingGestures = false
                if restoringActivation {
                    self.restoreFrontmostApp()
                }
            }
        }
    }

    /// Drives the open/close transition with one Core Animation transaction:
    /// the content scales (compositor transform) while the whole overlay
    /// fades (compositor opacity). No blur re-rasterization, no competing
    /// animation systems, so the transition stays smooth.
    private func animateOverlay(
        of window: NSWindow,
        open: Bool,
        completion: (() -> Void)? = nil
    ) {
        let duration: TimeInterval = open ? 0.15 : 0.18
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        window.contentView?.wantsLayer = true
        hostingView?.wantsLayer = true
        let contentLayer = window.contentView?.layer
        let scaleLayer = hostingView?.layer

        if open {
            contentLayer?.opacity = 0
            scaleLayer?.transform = CATransform3DScale(CATransform3DIdentity, 0.96, 0.96, 1)
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock {
            completion?()
        }

        if let contentLayer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = open ? 0 : 1
            fade.toValue = open ? 1 : 0
            fade.duration = duration
            fade.timingFunction = timing
            contentLayer.add(fade, forKey: "launchpadOverlayFade")
            contentLayer.opacity = open ? 1 : 0
        }
        if let scaleLayer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = open ? 0.96 : 1
            scale.toValue = open ? 1 : 0.96
            scale.duration = duration
            scale.timingFunction = timing
            scaleLayer.add(scale, forKey: "launchpadOverlayScale")
            scaleLayer.transform = CATransform3DScale(
                CATransform3DIdentity,
                open ? 1 : 0.96,
                open ? 1 : 0.96,
                1
            )
        }
        CATransaction.commit()
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
