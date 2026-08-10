import Foundation

/// Bundled assets shared by the app target and the login-item installer.
public enum AppAssets {
    /// The packaged app icon (`.icns`), embedded via the package resources.
    public static var iconURL: URL? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
    }

    /// The dedicated menu-bar icon (template PNG), embedded via the package
    /// resources. Falls back to the app icon when missing.
    public static var statusIconURL: URL? {
        Bundle.module.url(forResource: "StatusIcon", withExtension: "png")
    }
}
