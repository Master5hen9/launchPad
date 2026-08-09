import ApplicationServices
import SwiftUI
import launchPadCore

struct SettingsView: View {
    @AppStorage("pinchGestureEnabled", store: AppSettings.defaultsStore)
    private var pinchGestureEnabled = true

    @State private var loginItemInstalled = false
    @State private var loginItemStatus = ""
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var hiddenApps: [HiddenAppsStore.HiddenApp] = []
    @State private var isRecordingHotkey = false
    @State private var hotkeyRecorderMonitor: Any?
    @State private var hotkeyRegistrationFailed = false

    var body: some View {
        Form {
            Section("启动台") {
                Toggle("四指(或五指)聚拢打开", isOn: $pinchGestureEnabled)
                    .onChange(of: pinchGestureEnabled) { _, enabled in
                        AppDelegate.shared?.setPinchGestureEnabled(enabled)
                    }
                Text("若系统设置中「四指聚拢」绑定为搜索,请先在 系统设置 → 触控板 → 更多手势 中改为「无」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("立即打开启动台") {
                    AppDelegate.shared?.launchpad.open()
                }
            }

            Section("全局快捷键") {
                Toggle("启用全局快捷键", isOn: Binding(
                    get: { AppSettings.isGlobalHotkeyEnabled },
                    set: { enabled in
                        AppSettings.isGlobalHotkeyEnabled = enabled
                        AppDelegate.shared?.updateGlobalHotkey()
                        hotkeyRegistrationFailed = AppDelegate.shared?.hotkeyRegistrationFailed ?? false
                    }
                ))
                HStack {
                    Text("打开启动台的快捷键")
                    Spacer()
                    Button {
                        startRecordingHotkey()
                    } label: {
                        Text(isRecordingHotkey ? "按下新组合键…" : hotkeyDisplay)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!AppSettings.isGlobalHotkeyEnabled)
                }
                if hotkeyRegistrationFailed {
                    Text("快捷键注册失败，可能已被其他应用占用，请换一个组合。")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("默认 ⌘⇧空格。全局快捷键无需辅助功能权限，可在任何应用中唤起。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("全局手势权限") {
                if accessibilityTrusted {
                    Label("辅助功能已授权,后台手势监听已启用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("后台四指聚拢唤醒需要「辅助功能」权限。请在系统设置中勾选 launchPad,授权后应用会自动启用全局监听。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开辅助功能设置") {
                        openAccessibilitySettings()
                    }
                    Button("重新检测") {
                        accessibilityTrusted = AXIsProcessTrusted()
                    }
                }
            }

            Section("开机自启动") {
                Toggle("开机自动运行", isOn: Binding(
                    get: { loginItemInstalled },
                    set: { shouldInstall in
                        if shouldInstall {
                            installLoginItem()
                        } else {
                            uninstallLoginItem()
                        }
                    }
                ))
                if !loginItemStatus.isEmpty {
                    Text(loginItemStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("隐藏的应用") {
                if hiddenApps.isEmpty {
                    Text("没有隐藏的应用。在启动台中长按图标进入抖动模式，点击 × 即可隐藏或卸载应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(hiddenApps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(app.name)
                        Spacer()
                        Button("恢复") {
                            HiddenAppsStore.restore(appID: app.id)
                            hiddenApps = HiddenAppsStore.hiddenApps()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            loginItemInstalled = LoginItemInstaller.isInstalled()
            accessibilityTrusted = AXIsProcessTrusted()
            hiddenApps = HiddenAppsStore.hiddenApps()
            hotkeyRegistrationFailed = AppDelegate.shared?.hotkeyRegistrationFailed ?? false
        }
        .onDisappear {
            stopRecordingHotkey()
        }
    }

    private var hotkeyDisplay: String {
        let flags = NSEvent.ModifierFlags(rawValue: AppSettings.globalHotkeyModifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(AppSettings.globalHotkeyLabel)
        return parts.joined()
    }

    /// Captures the next key press (with ⌘/⌥/⌃ held) as the global shortcut.
    private func startRecordingHotkey() {
        isRecordingHotkey = true
        hotkeyRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode != 53 else { // Esc cancels
                self.stopRecordingHotkey()
                return nil
            }
            let required: NSEvent.ModifierFlags = [.command, .option, .control]
            guard event.modifierFlags.intersection(required) != [] else {
                return nil
            }
            AppSettings.globalHotkeyKeyCode = Int(event.keyCode)
            AppSettings.globalHotkeyModifiers = event.modifierFlags.rawValue
            if event.keyCode == 49 {
                AppSettings.globalHotkeyLabel = "空格"
            } else {
                AppSettings.globalHotkeyLabel = event.charactersIgnoringModifiers?.uppercased()
                    ?? "键\(event.keyCode)"
            }
            AppDelegate.shared?.updateGlobalHotkey()
            self.hotkeyRegistrationFailed = AppDelegate.shared?.hotkeyRegistrationFailed ?? false
            self.stopRecordingHotkey()
            return nil
        }
    }

    private func stopRecordingHotkey() {
        if let hotkeyRecorderMonitor {
            NSEvent.removeMonitor(hotkeyRecorderMonitor)
        }
        hotkeyRecorderMonitor = nil
        isRecordingHotkey = false
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func installLoginItem() {
        loginItemStatus = "正在安装…"
        Task {
            do {
                try LoginItemInstaller.install()
                loginItemInstalled = true
                loginItemStatus = "已安装,下次登录自动启动"
            } catch {
                loginItemInstalled = false
                loginItemStatus = error.localizedDescription
            }
        }
    }

    private func uninstallLoginItem() {
        loginItemStatus = "正在卸载…"
        Task {
            do {
                try LoginItemInstaller.uninstall()
                loginItemInstalled = false
                loginItemStatus = "已移除"
            } catch {
                loginItemInstalled = true
                loginItemStatus = error.localizedDescription
            }
        }
    }
}
