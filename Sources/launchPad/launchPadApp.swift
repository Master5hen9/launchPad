import AppKit
import SwiftUI
import launchPadCore

@main
struct launchPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// Shows the fullscreen Launchpad on demand: pinch gesture, Dock icon click,
/// or the `--show` launch argument.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let launchpad = LaunchpadWindowController()
    private var pinchMonitor: PinchGestureMonitor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Run as a menu-bar app: no Dock icon, just the status item.
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        applyPinchGestureSetting()
        NSLog("launchPad: 已启动;若四指聚拢被系统绑定(如搜索),请在 系统设置 → 触控板 → 更多手势 中改为「无」")
        handleLaunchArguments()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchpad.toggle()
        return true
    }

    func setPinchGestureEnabled(_ enabled: Bool) {
        AppSettings.isPinchGestureEnabled = enabled
        if enabled {
            startPinchMonitor()
        } else {
            stopPinchMonitor()
        }
    }

    private func applyPinchGestureSetting() {
        if AppSettings.isPinchGestureEnabled {
            startPinchMonitor()
        }
    }

    private func startPinchMonitor() {
        guard pinchMonitor == nil else { return }
        let monitor = PinchGestureMonitor(
            onPinchIn: { [weak self] in
                self?.launchpad.open()
            },
            onPinchOut: { [weak self] in
                self?.launchpad.close()
            },
            isConsumingEnabled: { [weak self] in
                self?.launchpad.isConsumingGestures ?? false
            }
        )
        monitor.start()
        pinchMonitor = monitor
    }

    private func stopPinchMonitor() {
        pinchMonitor?.stop()
        pinchMonitor = nil
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let iconURL = AppAssets.iconURL,
               let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(
                    systemSymbolName: "square.grid.2x2.fill",
                    accessibilityDescription: "launchPad"
                )
            }
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开启动台", action: #selector(openLaunchpad), keyEquivalent: "")
        openItem.target = self
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "退出 launchPad", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openLaunchpad() {
        launchpad.open()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func handleLaunchArguments() {
        if CommandLine.arguments.contains("--install-login-item") {
            installOrUninstallLoginItem(installing: true)
        } else if CommandLine.arguments.contains("--uninstall-login-item") {
            installOrUninstallLoginItem(installing: false)
        } else if CommandLine.arguments.contains("--show") {
            launchpad.open()
        }
    }

    private func installOrUninstallLoginItem(installing: Bool) {
        do {
            if installing {
                try LoginItemInstaller.install()
                print("launchPad: login item installed at \(LoginItemInstaller.agentPlistURL.path)")
            } else {
                try LoginItemInstaller.uninstall()
                print("launchPad: login item removed")
            }
        } catch {
            print("launchPad: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }
}
