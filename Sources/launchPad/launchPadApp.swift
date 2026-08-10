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
    private let globalHotkeyManager = GlobalHotkeyManager.shared
    /// Set when the configured shortcut is invalid or already claimed.
    private(set) var hotkeyRegistrationFailed = false
    private var directoryChangeObserver: (any NSObjectProtocol)?
    private let onboardingWindowController = OnboardingWindowController()
    private let settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Run as a menu-bar app: no Dock icon, just the status item.
        NSApp.setActivationPolicy(.accessory)
        launchpad.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        setupStatusItem()
        applyPinchGestureSetting()
        showOnboardingIfNeeded()
        updateGlobalHotkey()
        AppDirectoryMonitor.shared.start()
        directoryChangeObserver = NotificationCenter.default.addObserver(
            forName: AppDirectoryMonitor.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await AppCatalog.refresh()
            }
        }
        // Warm the app list in the background so the first Launchpad open
        // never shows the loading screen.
        Task { @MainActor in
            await AppCatalog.loadIfNeeded()
        }
        NSLog("launchPad: 已启动;若四指聚拢被系统绑定(如搜索),请在 系统设置 → 触控板 → 更多手势 中改为「无」")
        handleLaunchArguments()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDirectoryMonitor.shared.stop()
        globalHotkeyManager.unregister()
        if let directoryChangeObserver {
            NotificationCenter.default.removeObserver(directoryChangeObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchpad.toggle()
        return true
    }

    func setPinchGestureEnabled(_ enabled: Bool) {
        AppSettings.isPinchGestureEnabled = enabled
        if enabled {
            startPinchMonitor()
            if !PinchGestureMonitor.isAccessibilityTrusted {
                onboardingWindowController.open()
            }
        } else {
            stopPinchMonitor()
        }
    }

    @objc func showOnboarding() {
        onboardingWindowController.open()
    }

    private func applyPinchGestureSetting() {
        if AppSettings.isPinchGestureEnabled {
            startPinchMonitor()
        }
    }

    /// Shows the first-launch guide once; afterwards it is only available from
    /// the menu-bar menu (or when the pinch setting is re-enabled without
    /// Accessibility permission).
    private func showOnboardingIfNeeded() {
        guard !AppSettings.hasCompletedOnboarding else { return }
        onboardingWindowController.open()
    }

    /// (Re)registers the global shortcut from the current settings. Called on
    /// launch and whenever the user changes the shortcut in Settings.
    func updateGlobalHotkey() {
        guard AppSettings.isGlobalHotkeyEnabled else {
            globalHotkeyManager.unregister()
            hotkeyRegistrationFailed = false
            return
        }
        let keyCode = UInt32(AppSettings.globalHotkeyKeyCode)
        let modifiers = GlobalHotkeyManager.carbonModifiers(
            from: AppSettings.globalHotkeyModifiers
        )
        hotkeyRegistrationFailed = !globalHotkeyManager.register(
            keyCode: keyCode,
            modifiers: modifiers
        ) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    == Bundle.main.bundleIdentifier
                if isFrontmost, self.launchpad.isOpen, self.isCommaHotkey() {
                    // A Cmd+, global hotkey consumes the press before the app's
                    // own key handling runs. While the Launchpad overlay is up,
                    // route it to Settings; otherwise it is a plain toggle.
                    NSLog("launchPad: Cmd+, while launchpad open, opening settings")
                    self.launchpad.close(restoringActivation: false)
                    self.openSettings()
                } else {
                    self.launchpad.toggle()
                }
            }
        }
        NSLog(
            "launchPad: 全局快捷键注册%@ (keyCode=%d modifiers=%d)",
            hotkeyRegistrationFailed ? "失败" : "成功",
            keyCode,
            modifiers
        )
    }

    /// True when the configured global hotkey is plain `Cmd+,` (no Shift,
    /// Option or Control), which collides with the Settings shortcut.
    private func isCommaHotkey() -> Bool {
        guard AppSettings.globalHotkeyKeyCode == 43 else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: AppSettings.globalHotkeyModifiers)
        let required: NSEvent.ModifierFlags = [.command]
        let disallowed: NSEvent.ModifierFlags = [.shift, .control, .option]
        return flags.intersection(required) == required
            && flags.intersection(disallowed).isEmpty
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
        let guideItem = NSMenuItem(title: "首次使用引导…", action: #selector(showOnboarding), keyEquivalent: "")
        guideItem.target = self
        let quitItem = NSMenuItem(title: "退出 launchPad", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(settingsItem)
        menu.addItem(guideItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openLaunchpad() {
        launchpad.open()
    }

    @objc private func openSettings() {
        settingsWindowController.open()
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
        } else if CommandLine.arguments.contains("--open-settings") {
            openSettings()
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
