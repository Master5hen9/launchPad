import ApplicationServices
import SwiftUI
import launchPadCore

struct SettingsView: View {
    @AppStorage("pinchGestureEnabled", store: AppSettings.defaultsStore)
    private var pinchGestureEnabled = true

    @State private var loginItemInstalled = false
    @State private var loginItemStatus = ""
    @State private var accessibilityTrusted = AXIsProcessTrusted()

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
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            loginItemInstalled = LoginItemInstaller.isInstalled()
            accessibilityTrusted = AXIsProcessTrusted()
        }
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
