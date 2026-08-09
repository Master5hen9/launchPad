import ApplicationServices
import AppKit
import SwiftUI
import launchPadCore

/// First-launch guide: explains how to open the Launchpad and walks the user
/// through granting Accessibility, which the background pinch monitor needs.
struct OnboardingView: View {
    var onPermissionGranted: () -> Void
    var onDismiss: () -> Void

    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var trustTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            usageSection
            permissionSection
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("开始使用") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: accessibilityTrusted) { _, trusted in
            if trusted {
                onPermissionGranted()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("欢迎使用 launchPad")
                    .font(.title2.bold())
                Text("把 macOS 26 移除的启动台带回来")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appIcon: some View {
        Group {
            if let iconURL = AppAssets.iconURL,
               let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
            }
        }
        .frame(width: 56, height: 56)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("如何打开启动台")
                .font(.headline)
            usageRow(
                symbol: "hand.pinch",
                title: "四指或五指聚拢",
                detail: "在触控板上聚拢手指打开，张开手指关闭"
            )
            usageRow(
                symbol: "command",
                title: "全局快捷键",
                detail: "默认 ⌘⇧空格，在任意应用中都能唤起"
            )
            usageRow(
                symbol: "square.grid.2x2.fill",
                title: "菜单栏图标",
                detail: "点击菜单栏的 launchPad 图标，从菜单中打开启动台"
            )
        }
    }

    private func usageRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("后台手势权限")
                .font(.headline)
            if accessibilityTrusted {
                Label("辅助功能已授权，后台手势监听已启用", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("四指聚拢需要「辅助功能」权限才能在后台监听手势。点击下方按钮，在系统设置中勾选 launchPad，返回后本页会自动检测。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("打开辅助功能设置") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("重新检测") {
                            accessibilityTrusted = AXIsProcessTrusted()
                        }
                    }
                }
            }
        }
    }

    /// Polls Accessibility trust while the guide is visible so it can close
    /// itself as soon as the user grants the permission.
    private func startPolling() {
        guard trustTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                accessibilityTrusted = AXIsProcessTrusted()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func stopPolling() {
        trustTimer?.invalidate()
        trustTimer = nil
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
