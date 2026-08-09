import Foundation

/// Bundled assets shared by the app target and the login-item installer.
public enum AppAssets {
    /// The packaged app icon (`.icns`), embedded via the package resources.
    public static var iconURL: URL? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
    }
}
